defmodule CforumWeb.Views.ViewHelpers do
  @moduledoc """
  This module contains some helpers for web rendering
  """

  use Phoenix.HTML

  import CforumWeb.Gettext

  alias Cforum.Helpers
  alias Cforum.ConfigManager
  alias CforumWeb.Views.ViewHelpers.Path

  alias Cforum.ConfigManager
  alias Cforum.Helpers

  alias CforumWeb.Views.ViewHelpers.Path

  alias Phoenix.HTML.Form

  @doc """
  This function formats a date by a format name. It looks up the format itself
  using `Cforum.ConfigManager.uconf`. `name` parameter defaults to `"date_format_default"`.

  ## Examples

      iex> date_format(Timex.DateTime{})
      "2017-01-01 00:00"

      iex> date_format(Timex.DateTime{}, "date_format_default")
      "2017-01-01 00:00"
  """
  def date_format(conn, name \\ "date_format_default") do
    val = ConfigManager.uconf(conn, name)
    if Helpers.blank?(val), do: "%d.%m.%Y %H:%M", else: val
  end

  def local_date(date) do
    val =
      date
      |> Timex.to_datetime(:utc)
      |> Timex.to_datetime(Timex.Timezone.Local.lookup())

    case val do
      %Timex.AmbiguousDateTime{after: val} -> val
      val -> val
    end
  end

  def format_date(conn, date, format \\ "date_format_default"),
    do: Timex.format!(local_date(date), date_format(conn, format), :strftime)

  @doc """
  Returns true if a key in a changeset is blank or equal to a specified value. Helper for
  the user configuration and the admin interface, to distinguish between global config values
  and modified config values
  """
  def blank_or_value?(changeset, key, value) do
    field_val = Map.get(changeset, key)
    Helpers.blank?(field_val) || field_val == value
  end

  @doc """
  generates a „sub-form“ in a different namespace: the input fields will be prefixed
  with that namespace. If i.e. called with `field` set to `foo[bar]` the generated
  field names look like this: `foo[bar][baz]`
  """
  def sub_inputs(form, field, options \\ [], fun) do
    # options =
    #   form.options
    #   |> Keyword.take([:multipart])
    #   |> Keyword.merge(options)

    attr = Map.get(form.data, field) || %{}
    symbolized_attr = Enum.reduce(Map.keys(attr), %{}, fn key, map -> Map.put(map, String.to_atom(key), attr[key]) end)

    merged_attr =
      if options[:merge_callback],
        do: options[:merge_callback].(symbolized_attr),
        else: symbolized_attr

    types = Enum.reduce(Map.keys(merged_attr), %{}, fn key, map -> Map.put(map, key, :string) end)

    changeset = Ecto.Changeset.cast({merged_attr, types}, form.params, Map.keys(merged_attr))
    id = form.id <> "_#{field}"
    forms = Phoenix.HTML.FormData.to_form(changeset, as: form.name <> "[#{field}]")

    fun.(%Phoenix.HTML.Form{forms | id: id})
  end

  @doc """
  Generates a time tag with the correct `datetime` attribute and the given content
  """
  def time_tag(time, opts, do: content), do: time_tag(time, content, opts)

  def time_tag(time, content, opts) do
    timestamp = time_tag_timestamp(time)
    content_tag(:time, content, Keyword.merge([datetime: timestamp], opts))
  end

  @doc """
  Generates a textual timestamp representation suitable for a <time> tag
  """
  def time_tag_timestamp(%NaiveDateTime{} = time), do: NaiveDateTime.to_iso8601(time)
  def time_tag_timestamp(%DateTime{} = time), do: DateTime.to_iso8601(time)
  def time_tag_timestamp(%Date{} = time), do: Date.to_iso8601(time)

  @doc """
  Renders a localized version of the template.

  Sometimes it is useful to have a localized partial or template, containing blocks of
  HTML and text mixed. `l10n_render/3` tries to render this localized version and falls
  back to the non-localized version, e.g. given locale is `de`,
  `l10n_render(@view_module, "foo.html", assigns)`` first tries to render `foo.de.html`
  and then, when not successful, falls back to `foo.html`.

  ## Parameters

  - `view` - the view module (e.g. `@view_module`)
  - `template` - the template file name
  - `assigns` - assigned variables/values
  """
  def l10n_render(view, template, assigns) do
    locale = Gettext.get_locale(CforumWeb.Gettext)
    val = Phoenix.View.render_existing(view, String.replace_suffix(template, ".html", ".#{locale}.html"), assigns)
    if val == nil, do: Phoenix.View.render(view, template, assigns), else: val
  end

  @doc """
  Try to get a pre-filled author from the conn

  Either by `current_user.username` or by `cforum_author` cookie
  """
  def author_from_conn(%{assigns: %{current_user: user}}) when not is_nil(user), do: user.username
  def author_from_conn(conn), do: conn.cookies["cforum_author"]

  @doc """
  Try to get the email address from the conn

  Either from user configuration or from `cforum_email` cookie
  """
  def email_from_conn(%{assigns: %{current_user: user}} = conn) when not is_nil(user),
    do: ConfigManager.uconf(conn, "email")

  def email_from_conn(conn), do: conn.cookies["cforum_email"]

  @doc """
  Try to get the homepage address from the conn

  Either from user config or from the `cforum_homepage` cookie
  """
  def homepage_from_conn(%{assigns: %{current_user: user}} = conn) when not is_nil(user),
    do: ConfigManager.uconf(conn, "url")

  def homepage_from_conn(conn), do: conn.cookies["cforum_homepage"]

  @doc """
  Returns the localized medal type name
  """
  def l10n_medal_type("bronze"), do: gettext("bronze medal")
  def l10n_medal_type("silver"), do: gettext("silver medal")
  def l10n_medal_type("gold"), do: gettext("gold medal")
  def l10n_medal_type(v), do: raise(inspect(v))

  def l10n_badge_type("upvote"), do: gettext("upvote")
  def l10n_badge_type("downvote"), do: gettext("downvote")
  def l10n_badge_type("retag"), do: gettext("retag")
  def l10n_badge_type("create_tag"), do: gettext("create tags")
  def l10n_badge_type("create_tag_synonym"), do: gettext("create tag synonyms")
  def l10n_badge_type("edit_question"), do: gettext("edit questions")
  def l10n_badge_type("edit_answer"), do: gettext("edit answers")
  def l10n_badge_type("moderator_tools"), do: gettext("moderator tools")
  def l10n_badge_type("seo_profi"), do: gettext("seo profi")
  def l10n_badge_type("custom"), do: gettext("custom")

  def user_link(conn, user, additional_classes \\ [], username \\ "", do_link \\ true) do
    user_name = if Cforum.Helpers.blank?(username), do: "", else: " #{username}"

    content = [
      {:safe, "<span class=\"registered-user "},
      additional_classes,
      {:safe, "\">"},
      img_tag(Cforum.Users.User.avatar_path(user, :thumb), class: "avatar", alt: ""),
      user_name,
      {:safe, "</span>"}
    ]

    if do_link do
      link(content,
        to: Path.user_path(conn, :show, user),
        title: gettext("user %{user}", user: user.username),
        class: "user-link"
      )
    else
      content
    end
  end

  def controller(conn) do
    if conn.assigns[:is_error],
      do: CforumWeb.ErrorView,
      else: Phoenix.Controller.controller_module(conn)
  rescue
    _ in KeyError -> CforumWeb.ForumController
  end

  def controller_path(conn) do
    conn
    |> controller()
    |> Atom.to_string()
    |> String.replace(~r{^Elixir\.CforumWeb\.}, "")
    |> String.replace(~r{Controller$}, "")
    |> Macro.underscore()
  end

  def std_args(conn, args \\ %{})
  def std_args(conn, args) when is_list(args), do: std_args(conn, Enum.into(args, %{}))

  def std_args(conn, args) do
    local_args =
      %{
        p: conn.params["p"],
        page: conn.params["page"],
        r: controller_path(conn),
        f: Path.forum_slug(conn.assigns[:current_forum])
      }
      |> Enum.filter(fn {_k, v} -> !Helpers.blank?(v) end)
      |> Enum.into(%{})

    Map.merge(local_args, args)
  end

  def date_time_combo(form, name, opts \\ []) do
    value = opts[:value] || Form.input_value(form, name)

    {date_value, time_value} =
      case value do
        nil -> {nil, nil}
        v -> {Timex.to_date(v), v |> Timex.local() |> DateTime.to_time()}
      end

    base_name = Form.input_name(form, name)

    [
      {:safe, "<div class=\"datetime\">"},
      Form.date_input(form, name, Keyword.merge(opts, name: "#{base_name}[date]", value: date_value)),
      Form.time_input(form, name, Keyword.merge(opts, name: "#{base_name}[time]", value: time_value)),
      {:safe, "</div>"}
    ]
  end

  def concat_datetime(params, name) do
    if params[name] && Map.has_key?(params[name], "date") && Map.has_key?(params[name], "time") do
      if Helpers.present?(get_in(params, [name, "date"])) && Helpers.present?(get_in(params, [name, "time"])),
        do: Map.put(params, name, "#{params[name]["date"]} #{params[name]["time"]}"),
        else: Map.put(params, name, "")
    else
      params
    end
  end
end
