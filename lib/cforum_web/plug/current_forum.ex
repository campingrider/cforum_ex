defmodule CforumWeb.Plug.CurrentForum do
  @moduledoc """
  This plug is plugged in the browser pipeline and loads and assigns the current
  forum; if the forum could not be found it throws an 404 error
  """

  alias Plug.Conn
  alias Cforum.Forums
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    path = List.first(conn.path_info)

    conn
    |> maybe_put_forum(path)
    |> maybe_modify_path(path)
  end

  defp maybe_put_forum(conn, "all"), do: Conn.assign(conn, :current_forum, nil)
  defp maybe_put_forum(conn, ""), do: Conn.assign(conn, :current_forum, nil)
  defp maybe_put_forum(conn, nil), do: Conn.assign(conn, :current_forum, nil)

  defp maybe_put_forum(conn, slug) do
    forum = Forums.get_forum_by_slug(slug)
    Conn.assign(conn, :current_forum, forum)
  end

  defp maybe_modify_path(conn, "all"), do: replace_infos_with__forum(conn, "all")
  defp maybe_modify_path(%{assigns: %{current_forum: nil}} = conn, _), do: conn

  defp maybe_modify_path(conn, slug), do: replace_infos_with__forum(conn, slug)

  defp replace_infos_with__forum(conn, slug) do
    {_, pi} = List.pop_at(conn.path_info, 0)

    %Conn{
      conn
      | path_info: ["__forum"] ++ pi,
        request_path: String.replace(conn.request_path, "/" <> slug, "/__forum")
    }
  end
end
