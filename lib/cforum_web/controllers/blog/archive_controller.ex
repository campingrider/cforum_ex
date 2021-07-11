defmodule CforumWeb.Blog.ArchiveController do
  use CforumWeb, :controller

  alias Cforum.Abilities
  alias Cforum.Threads
  alias Cforum.Threads.Archive
  alias Cforum.ConfigManager

  alias CforumWeb.Paginator

  def years(conn, _) do
    years =
      Archive.list_archive_years(conn.assigns[:current_forum], conn.assigns[:visible_forums],
        view_all: conn.assigns[:view_all]
      )

    render(conn, "years.html", years: years)
  end

  @month_names [nil] ++ ~w[jan feb mar apr may jun jul aug sep oct nov dec]

  def threads(conn, %{"year" => year, "month" => month_name} = params) do
    if month_name =~ ~r/^\d+$/ do
      month = Enum.at(@month_names, String.to_integer(month_name, 10))
      redirect(conn, to: "/#{year}/#{month}")
    else
      render_threads(conn, params, year, month_name)
    end
  end

  def render_threads(conn, params, year, month_name) do
    if !Regex.match?(~r/^\d+$/, year) || month_name not in @month_names,
      do: raise(Cforum.Errors.NotFoundError, conn: conn)

    case NaiveDateTime.new(String.to_integer(year), Timex.month_to_num(month_name), 1, 0, 0, 0) do
      {:ok, month} ->
        start_date = Timex.beginning_of_month(month)
        end_date = Timex.end_of_month(month)
        page = Paginator.parse_page(params["p"]) - 1
        limit = ConfigManager.uconf(conn, "pagination", :int)

        threads =
          conn.assigns[:current_forum]
          |> Archive.list_archived_threads(conn.assigns[:visible_forums], start_date, end_date,
            view_all: conn.assigns[:view_all],
            limit: limit,
            page: page,
            order: "ascending"
          )
          |> Threads.reject_deleted_threads(conn.assigns[:view_all], true)
          |> Threads.reject_drafts(conn.assigns[:view_all])
          |> Threads.apply_user_infos(conn.assigns[:current_user],
            close_read_threads: ConfigManager.uconf(conn, "open_close_close_when_read") == "yes",
            open_close_default_state: ConfigManager.uconf(conn, "open_close_default")
          )
          |> Threads.apply_highlights(conn)
          |> Threads.build_message_trees(ConfigManager.uconf(conn, "sort_messages"))

        count =
          Archive.count_archived_threads(
            conn.assigns[:current_forum],
            conn.assigns[:visible_forums],
            start_date,
            end_date,
            view_all: conn.assigns[:view_all]
          )

        p = Paginator.paginate(count, per_page: limit, page: page + 1)

        render(conn, "threads.html", threads: threads, page: p, start_date: start_date)

      _ ->
        conn
        |> put_status(:not_found)
        |> put_view(CforumWeb.ErrorView)
        |> render("404.html")
    end
  end

  def allowed?(conn, _, _), do: Abilities.access_forum?(conn)
end
