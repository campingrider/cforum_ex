defmodule CforumWeb.LayoutView do
  use CforumWeb, :view

  alias Cforum.Search

  alias Cforum.Abilities
  alias Cforum.ConfigManager
  alias Cforum.Helpers

  alias CforumWeb.Views.ViewHelpers
  alias CforumWeb.Views.ViewHelpers.Path

  def page_title(conn, assigns) do
    if Kernel.function_exported?(view_module(conn), :page_title, 2),
      do: apply(view_module(conn), :page_title, [action_name(conn), assigns]) |> maybe_append_forum(assigns),
      else: default_page_title(conn, assigns)
  end

  defp maybe_append_forum(str, assigns) do
    appendix =
      cond do
        is_nil(assigns[:current_forum]) -> " – SELFHTML Forum"
        assigns[:current_forum].type == "blog" -> " – SELFHTML Weblog"
        assigns[:current_forum].type == "forum" -> " – SELFHTML Forum"
        true -> ""
      end

    str <> appendix
  end

  def default_page_title(_conn, assigns) do
    cond do
      is_nil(assigns[:current_forum]) -> "SELFHTML Forum"
      assigns[:current_forum].type == "blog" -> "SELFHTML Weblog"
      assigns[:current_forum].type == "forum" -> "SELFHTML Forum"
      true -> "SELFHTML Forum"
    end
  end

  def body_classes(conn, assigns, blog \\ false) do
    anon_class =
      if Helpers.blank?(conn.assigns[:current_user]),
        do: "anonymous",
        else: "registered"

    classes =
      if Kernel.function_exported?(view_module(conn), :body_classes, 2),
        do: apply(view_module(conn), :body_classes, [action_name(conn), assigns]),
        else: ""

    weblog_class =
      if blog,
        do: " weblog",
        else: ""

    [{:safe, "class=\""}, classes, weblog_class, " ", anon_class, " ", holiday_classes(conn), {:safe, "\""}]
  end

  def body_id(conn, assigns) do
    if Kernel.function_exported?(view_module(conn), :body_id, 2),
      do: {:safe, " id=\"#{apply(view_module(conn), :body_id, [action_name(conn), assigns])}\""},
      else: ""
  end

  def page_heading(conn, assigns) do
    with true <- Kernel.function_exported?(view_module(conn), :page_heading, 2),
         heading when is_binary(heading) <- apply(view_module(conn), :page_heading, [action_name(conn), assigns]) do
      [{:safe, "<h1>"}, heading, {:safe, "</h1>"}]
    else
      _ -> ""
    end
  end

  def meta_refresh(conn) do
    path = ViewHelpers.controller_path(conn)
    action = Phoenix.Controller.action_name(conn)
    refresh = ConfigManager.uconf(conn, "autorefresh", :int)

    if path == "thread" and action == :index and refresh > 0 do
      [
        {:safe, "<meta http-equiv=\"refresh\" content=\""},
        Integer.to_string(refresh * 60),
        {:safe, "; URL="},
        Path.forum_url(conn, :index, conn.assigns[:current_forum]),
        {:safe, "\">"}
      ]
    else
      ""
    end
  end

  def own_css(conn) do
    css = ConfigManager.uconf(conn, "own_css")

    if Helpers.blank?(css),
      do: "",
      else: [
        {:safe, "<style nonce=\""},
        conn.assigns[:nonce_for_style],
        {:safe, "\">\n"},
        {:safe, css},
        {:safe, "\n</style>"}
      ]
  end

  def own_css_file(conn) do
    css = ConfigManager.uconf(conn, "own_css_file")

    if Helpers.blank?(css) do
      ""
    else
      [
        {:safe, "<link href=\""},
        css,
        {:safe, "\" rel=\"stylesheet\" media=\"all\" title=\"SELFHTML Forum Stylesheet\" nonce=\""},
        conn.assigns[:nonce_for_style],
        {:safe, "\">"}
      ]
    end
  end

  def own_js(conn) do
    js = ConfigManager.uconf(conn, "own_js")

    if Helpers.blank?(js),
      do: "",
      else: [
        {:safe, "<script nonce=\""},
        conn.assigns[:nonce_for_js],
        {:safe, "\">\n"},
        {:safe, js},
        {:safe, "\n</script>"}
      ]
  end

  def own_js_file(conn) do
    js = ConfigManager.uconf(conn, "own_js_file")

    if Helpers.blank?(js),
      do: "",
      else: [
        {:safe, "<script nonce=\""},
        conn.assigns[:nonce_for_js],
        {:safe, "\" src=\""},
        js,
        {:safe, "\"></script>"}
      ]
  end

  def css_ressource(conn) do
    css = ConfigManager.uconf(conn, "css_ressource")

    if Helpers.blank?(css) do
      ""
    else
      [
        {:safe, "<link href=\""},
        css,
        {:safe, "\" rel=\"stylesheet\" media=\"all\" title=\"SELFHTML Forum Stylesheet\" nonce=\""},
        conn.assigns[:nonce_for_style],
        {:safe, "\">"}
      ]
    end
  end

  def include_mathjax?(conn, url) do
    cond do
      controller_module(conn) == CforumWeb.MessageController -> true
      controller_module(conn) == CforumWeb.ThreadController && action_name(conn) == :new -> true
      controller_module(conn) == CforumWeb.MailController && action_name(conn) in [:show, :new, :create] -> true
      true -> false
    end &&
      Helpers.present?(url)
  end

  def mathjax(conn) do
    url = ConfigManager.conf(conn, "mathjax_url")

    if include_mathjax?(conn, url) do
      [
        {:safe, "<script nonce=\""},
        conn.assigns[:nonce_for_js],
        {:safe, "\">"},
        {:safe,
         """
           window.MathJax = {
             displayAlign: "left",
             messageStyle: "none",
             showMathMenu: false,
             menuSettings: { CHTMLpreview: false },
             tex2jax: {
               inlineMath: [['$$', '$$']],
               displayMath: [],
               preview: "none",
               processEscapes: true
             }
           };
         </script>
         """},
        {:safe, "<script src=\""},
        url,
        {:safe, "\" async></script>\n"}
      ]
    else
      ""
    end
  end

  def show?(%{is_error: true}, _), do: false

  def show?(%{conn: conn}, :archive) do
    Enum.member?(
      [CforumWeb.ThreadController, CforumWeb.MessageController, CforumWeb.ArchiveController],
      ViewHelpers.controller(conn)
    )
  end

  def show?(%{conn: conn}, link) when link in [:events, :badges],
    do: ViewHelpers.controller(conn) == CforumWeb.ForumController

  def show?(%{conn: conn}, :thread_feeds),
    do: Helpers.present?(conn.assigns[:thread]) && Helpers.present?(conn.assigns[:thread].thread_id)

  def show?(%{conn: conn}, :search),
    do: ViewHelpers.controller(conn) != CforumWeb.SearchController

  def show?(%{conn: conn}, :sort_links) do
    ViewHelpers.controller(conn) == CforumWeb.ThreadController && Helpers.blank?(conn.assigns[:current_user]) &&
      action_name(conn) not in [:new, :create, :edit, :update]
  end

  def show?(%{conn: conn}, :thread_nested) do
    Helpers.present?(conn.assigns[:message]) && Helpers.present?(conn.assigns[:thread]) &&
      Helpers.present?(conn.assigns[:read_mode]) &&
      Helpers.present?(conn.assigns[:message].message_id)
  end

  @view_all_enabled_controllers [
    CforumWeb.ThreadController,
    CforumWeb.MessageController,
    CforumWeb.Messages.VersionController,
    CforumWeb.ArchiveController,
    CforumWeb.Blog.IndexController,
    CforumWeb.Blog.ArticleController,
    CforumWeb.Blog.ArchiveController
  ]

  def show?(%{conn: conn}, :view_all) do
    Abilities.access_forum?(conn, :moderate) &&
      Enum.member?(@view_all_enabled_controllers, ViewHelpers.controller(conn))
  end

  def show?(%{conn: conn}, :mark_all_read) do
    Helpers.present?(conn.assigns[:threads]) && Helpers.present?(conn.assigns[:current_user]) &&
      ViewHelpers.controller(conn) == CforumWeb.ThreadController
  end

  def sort_link(conn, params),
    do: (conn.assigns[:original_path] || conn.request_path) <> Path.encode_query_string(params)

  def search_changeset(conn) do
    visible_sections =
      cond do
        controller_module(conn) == CforumWeb.CiteController ->
          Search.list_visible_search_sections(conn.assigns.visible_forums, "cites")

        Helpers.present?(conn.assigns[:current_forum]) ->
          Search.list_visible_search_sections(conn.assigns.visible_forums, "forum")
          |> Enum.filter(&(&1.forum_id == conn.assigns[:current_forum].forum_id))

        true ->
          Search.list_visible_search_sections(conn.assigns.visible_forums, "forum")
      end

    Search.search_changeset(visible_sections, %{sections: Enum.map(visible_sections, & &1.search_section_id)})
  end

  def sections(form), do: Ecto.Changeset.get_field(form.source, :sections, [])

  def numeric_infos(conn, %{current_user: user} = assigns) when not is_nil(user) do
    str =
      ""
      |> unread_notifications(ConfigManager.uconf(conn, "show_unread_notifications_in_title"), assigns)
      |> unread_pms(ConfigManager.uconf(conn, "show_unread_pms_in_title"), assigns)
      |> new_messages(ConfigManager.uconf(conn, "show_new_messages_since_last_visit_in_title"), assigns)
      |> String.trim("/")

    if Helpers.present?(str), do: "(#{str}) ", else: ""
  end

  def numeric_infos(_, _), do: ""

  defp unread_notifications(str, "no", _), do: str
  defp unread_notifications(str, "yes", assigns), do: "#{str}#{assigns[:unread_notifications]}"
  defp unread_pms(str, "no", _), do: str
  defp unread_pms(str, "yes", assigns), do: "#{str}/#{assigns[:unread_mails]}"
  defp new_messages(str, "no", _), do: str
  defp new_messages(str, "yes", assigns), do: "#{str}/#{assigns[:unread_messages]}"

  def view_all_link(conn) do
    opts =
      if conn.assigns[:view_all],
        do: [view_all: nil],
        else: [view_all: "yes"]

    controller = ViewHelpers.controller(conn)

    path =
      cond do
        controller == CforumWeb.Messages.VersionController ->
          Path.message_version_path(conn, :index, conn.assigns[:thread], conn.assigns[:message], opts)

        Helpers.present?(conn.assigns[:article]) && controller == CforumWeb.Blog.ArticleController ->
          Path.blog_thread_path(conn, :show, conn.assigns[:article], opts)

        controller == CforumWeb.Blog.ArchiveController && Helpers.present?(conn.assigns[:years]) ->
          Path.blog_archive_path(conn, :years, opts)

        controller == CforumWeb.Blog.ArchiveController ->
          Path.blog_archive_path(conn, :threads, conn.assigns[:start_date], opts)

        controller == CforumWeb.Blog.IndexController ->
          Path.blog_url(conn, opts)

        Helpers.present?(conn.assigns[:message]) ->
          Path.message_path(conn, :show, conn.assigns[:thread], conn.assigns[:message], opts)

        true ->
          Path.forum_path(conn, :index, conn.assigns[:current_forum], opts)
      end

    if conn.assigns[:view_all],
      do: link(gettext("normal view"), to: path),
      else: link(gettext("administrative view"), to: path)
  end

  def chat_nick_name(conn) do
    nick =
      if conn.assigns[:current_user],
        do: conn.assigns[:current_user].username,
        else: "Guest_" <> Integer.to_string(Enum.random(1..9999))

    Path.encode_query_string(%{"nick" => nick})
  end

  def forum_name(nil), do: gettext("all forums")
  def forum_name(forum), do: forum.name

  def user_id(conn) do
    cond do
      Helpers.present?(conn.assigns[:current_user]) ->
        [{:safe, " data-user-id=\""}, to_string(conn.assigns.current_user.user_id), {:safe, "\""}]

      Helpers.present?(conn.cookies["cforum_user"]) ->
        [{:safe, " data-uuid=\""}, to_string(conn.cookies["cforum_user"]), {:safe, "\""}]

      true ->
        ""
    end
  end

  def current_controller(conn) do
    conn
    |> ViewHelpers.controller()
    |> Atom.to_string()
    |> String.replace(~r/Elixir\.Cforum(Web)?\./, "")
  end

  defp holiday_classes(_conn) do
    today = Timex.today()

    cond do
      today.month == 12 || (today.month == 1 && today.day < 5) -> "christmas"
      today.month == 11 && today.day == 30 -> "blue-beanie"
      true -> ""
    end
  end

  def login_link(conn) do
    controller = current_controller(conn)

    cond do
      controller == "MessageController" && conn.assigns[:message] ->
        Path.session_path(conn, :new, return_to: conn.assigns.message.message_id)

      controller == "Blog.ArticleController" && conn.assigns[:article] ->
        Path.session_path(conn, :new, return_to: conn.assigns.article.message.message_id)

      true ->
        Path.session_path(conn, :new)
    end
  end
end
