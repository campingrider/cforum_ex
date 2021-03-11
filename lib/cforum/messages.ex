defmodule Cforum.Messages do
  @moduledoc """
  The boundary for the Forums system.
  """

  import Ecto.Query, warn: false

  alias Cforum.Repo
  alias Cforum.Helpers

  alias Cforum.Messages.Message

  alias Cforum.Scores
  alias Cforum.Notifications

  alias Cforum.System

  alias Cforum.Threads
  alias Cforum.Threads.Thread
  alias Cforum.Threads.ThreadCaching

  alias Cforum.Jobs.MessageIndexerJob
  alias Cforum.Jobs.UnindexMessageJob
  alias Cforum.Jobs.RescoreMessageJob
  alias Cforum.Jobs.NotifyUsersMessageJob
  alias Cforum.Jobs.NewMessageBadgeDistributorJob

  alias Cforum.Messages.Mentions
  alias Cforum.Subscriptions
  alias Cforum.Messages.MessageHelpers
  alias Cforum.Messages.MessageVersions
  alias Cforum.Messages.MessageCaching

  alias Cforum.Helpers.CompositionHelpers

  @spec list_messages([any]) :: [Message.t()]
  def list_messages(message_ids) do
    threads = Threads.get_threads_by_message_ids(message_ids)

    threads
    |> Enum.flat_map(fn thread ->
      Enum.map(thread.messages, &%Message{&1 | thread: thread})
    end)
    |> Enum.filter(&(&1.message_id in message_ids))
  end

  @doc """
  Gets a single message.

  Leaves out deleted messages by default; if you want to retrieve
  deleted messages, set `view_all: true` as second parameter

  Raises `Ecto.NoResultsError` if the Message does not exist.

  ## Examples

      iex> get_message!(123)
      %Message{}

      iex> get_message!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_message!(any, nil | maybe_improper_list | map) :: Message.t()
  def get_message!(id, opts \\ []) do
    if opts[:view_all],
      do: Repo.get!(Message, id),
      else: Repo.get_by!(Message, message_id: id, deleted: false)
  end

  @doc """
  Gets a single message.

  Leaves out deleted messages by default; if you want to retrieve
  deleted messages, set `view_all: true` as second parameter

  Returns nil if the Message does not exist.

  ## Examples

      iex> get_message(123)
      %Message{}

      iex> get_message(456)
      nil

  """
  @spec get_message(any, maybe_improper_list | map) :: Message.t() | nil
  def get_message(id, opts \\ []) do
    if opts[:view_all],
      do: Repo.get(Message, id),
      else: Repo.get_by(Message, message_id: id, deleted: false)
  end

  @doc """
  Gets a thread with all messages and a single message. Returns a
  tuple `{%Thread{}, %Message{}}`.

  Leaves out deleted messages by default; if you want to retrieve
  deleted messages, set `view_all: true` as second parameter

  Raises `Ecto.NoResultsError` if the Message does not exist.

  - `forum` is the current forum
  - `visible_forums` is a list of forums the user may look at
  - `user` is the current user
  - `thread_id` is the thread id
  - `message_id` is the message id
  - `opts` is an option list as defined by `Cforum.Threads.list_threads/4`

  ## Examples

      iex> get_message_and_thread!(nil, nil, nil, 1, 2)
      {%Thread{}, %Message{}}

      iex> get_message_and_thread(nil, nil, nil, -1, 1)
      ** (Ecto.NoResultsError)

  """
  @spec get_message_and_thread!(
          Cforum.Forums.Forum.t() | nil,
          [Cforum.Forums.Forum.t()] | nil,
          any,
          any,
          maybe_improper_list | map
        ) :: {Thread.t(), Message.t()}
  def get_message_and_thread!(forum, visible_forums, thread_id, message_id, opts \\ []) do
    thread =
      forum
      |> Threads.get_thread!(visible_forums, thread_id)
      |> Threads.reject_deleted_threads(opts[:view_all])

    case MessageHelpers.find_message(thread, &(&1.message_id == message_id)) do
      nil ->
        raise Ecto.NoResultsError, queryable: Message

      msg ->
        {thread, msg}
    end
  end

  @doc """
  sort messages either ascending or descending
  """
  @spec sort_messages([Message.t()], String.t()) :: [Message.t()]
  def sort_messages(messages, direction) do
    Enum.sort(messages, fn a, b ->
      cond do
        a.parent_id == b.parent_id && direction == "ascending" -> Timex.compare(a.created_at, b.created_at) <= 0
        a.parent_id == b.parent_id && direction == "descending" -> Timex.compare(a.created_at, b.created_at) >= 0
        true -> Cforum.Helpers.to_int(a.parent_id) <= Cforum.Helpers.to_int(b.parent_id)
      end
    end)
  end

  @doc """
  Loads a thread by its slug and searches for the message specified my `mid` in the thread tree. Sets things like
  visited marks, etc, pp. Raises `Ecto.NoResultsError` when no thread or no message could be found.

  ## Examples

      iex> get_message_from_mid!(%Forum{}, %User{}, "2009/08/25/foo-bar", 222)
      {%Thread{}, %Message{}}

      iex> get_message_from_mid!(%Forum{}, %User{}, "2009/08/32/foo-bar", 222)
      ** (Ecto.NoResultsError)
  """
  @spec get_message_from_mid!(Thread.t(), any) :: Message.t()
  def get_message_from_mid!(thread, mid)

  def get_message_from_mid!(thread, mid) when is_bitstring(mid),
    do: get_message_from_mid!(thread, String.to_integer(mid, 10))

  def get_message_from_mid!(%Thread{} = thread, mid) do
    case MessageHelpers.find_message(thread, &(&1.message_id == mid)) do
      nil -> raise Ecto.NoResultsError, queryable: Message
      msg -> msg
    end
  end

  @spec get_message_from_old_mid!(Thread.t(), any) :: Message.t()
  def get_message_from_old_mid!(thread, mid) when is_bitstring(mid),
    do: get_message_from_old_mid!(thread, String.to_integer(mid, 10))

  def get_message_from_old_mid!(thread, mid) do
    case MessageHelpers.find_message(thread, &(&1.mid == mid)) do
      nil -> raise Ecto.NoResultsError, queryable: Message
      msg -> msg
    end
  end

  @doc """
  Creates a message.

  ## Parameters

  attrs: the message attributes, e.g. `:subject`
  user: the current user
  visible_forums: the forums visible to the current user
  thread: the thread the message belongs to
  parent: the parent message of the new message

  ## Examples

      iex> create_message(%{field: value}, %User{}, [%Forum{}], %Thread{})
      {:ok, %Message{}}

      iex> create_message(%{field: bad_value}, %User{}, [%Forum{}], %Thread{})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_message(map, %{user_id: any} | nil, [%{forum_id: any}], Thread.t(), Message.t() | nil, keyword) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_message(attrs, user, visible_forums, thread, parent \\ nil, opts \\ []) do
    opts = Keyword.merge([create_tags: false, autosubscribe: false, notify: true], opts)

    System.audited("create", user, fn ->
      changeset =
        %Message{}
        |> Message.changeset(attrs, user, visible_forums, thread, parent, opts)
        |> Mentions.parse_mentions()

      author = Ecto.Changeset.get_field(changeset, :author)

      case MessageHelpers.may_user_post_with_name?(user, author) do
        true ->
          Repo.insert(changeset)
          |> maybe_attach_thumbnail(attrs)

        _ ->
          changeset =
            changeset
            |> Map.put(:action, :insert)
            |> Ecto.Changeset.add_error(:author, "has already been taken")

          {:error, changeset}
      end
    end)
    |> notify_users(thread, opts[:notify])
    |> Subscriptions.maybe_autosubscribe(opts[:autosubscribe], user, thread, parent)
    |> index_message(thread)
    |> maybe_distribute_badges()
    |> ThreadCaching.refresh_cached_thread()
  end

  defp maybe_attach_thumbnail({:ok, message}, attrs) do
    forum = Cforum.Forums.get_forum!(message.forum_id)

    if forum.type == "blog" do
      message
      |> Message.attachment_changeset(attrs)
      |> Ecto.Changeset.change(%{updated_at: message.created_at})
      |> Repo.update()
    else
      {:ok, message}
    end
  end

  defp maybe_attach_thumbnail(v, _), do: v

  defp index_message({:ok, message}, thread) do
    MessageIndexerJob.enqueue(thread, message)
    {:ok, message}
  end

  defp index_message(val, _), do: val

  defp maybe_distribute_badges({:ok, message}) do
    NewMessageBadgeDistributorJob.enqueue(message)
    {:ok, message}
  end

  defp maybe_distribute_badges(val), do: val

  @default_notification_types ["message:create-answer", "message:create-activity"]
  @spec unnotify_user(Cforum.Users.User.t(), String.t(), Thread.t(), Message.t(), [String.t()]) :: any
  def unnotify_user(user, read_mode, thread, message, notification_types \\ @default_notification_types)
  def unnotify_user(user, _, _, message, _) when is_nil(user) or is_nil(message), do: nil

  def unnotify_user(user, "thread", _, message, types),
    do: Notifications.delete_notification_for_object(user, message.message_id, types)

  def unnotify_user(user, _, thread, _, types) do
    mids = Enum.map(thread.sorted_messages, & &1.message_id)
    Notifications.delete_notification_for_object(user, mids, types)
  end

  @spec unnotify_user({:ok, Message.t()} | {:error, Ecto.Changeset.t()}, [any]) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def unnotify_user({:ok, msg}, message_ids) do
    Notifications.delete_notifications_for_objects(message_ids, [
      "message:create-answer",
      "message:create-activity",
      "message:mention"
    ])

    {:ok, msg}
  end

  def unnotify_user(val, _), do: val

  @doc """
  Generates a %Message{} and a changeset for preview purposes

  ## Parameters

  attrs: The message attributes
  user: The current user
  thread: The thread the message belongs to
  parent: the parent message

  ## Examples

      iex> preview_message(%{}, %User{}, %Thread{})
      {%Message{}, %Ecto.Changeset{}}
  """
  @spec preview_message(
          map,
          Cforum.Users.User.t(),
          [Cforum.Forums.Forum.t()],
          Thread.t(),
          Message.t() | nil,
          Message.t()
        ) :: {Message.t(), Ecto.Changeset.t()}
  def preview_message(attrs, user, visible_forums, thread, parent \\ nil, message \\ %Message{created_at: Timex.now()}) do
    changeset = Message.changeset(message, attrs, user, visible_forums, thread, parent)

    msg = %Message{
      Ecto.Changeset.apply_changes(changeset)
      | tags: Ecto.Changeset.get_field(changeset, :tags),
        user: user
    }

    {msg, %Ecto.Changeset{changeset | action: :insert}}
  end

  @doc """
  Updates a message.

  ## Examples

      iex> update_message(message, %{field: new_value})
      {:ok, %Message{}}

      iex> update_message(message, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_message(Message.t(), map(), Cforum.Users.User.t() | nil, [Cforum.Forums.Forum.t()], keyword()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def update_message(%Message{} = message, attrs, user, visible_forums, opts \\ [create_tags: false]) do
    System.audited("update", user, fn ->
      message
      |> Message.update_changeset(attrs, user, visible_forums, opts)
      |> Mentions.parse_mentions()
      |> MessageVersions.build_version(message, user)
      |> Repo.update()
      |> maybe_attach_thumbnail(attrs)
      |> MessageCaching.update_cached_message()
    end)
  end

  @spec retag_message(Message.t(), map(), Cforum.Users.User.t(), keyword()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def retag_message(%Message{} = message, attrs, user, opts \\ [create_tags: false, retag_children: false]) do
    System.audited("retag", user, fn ->
      ret =
        message
        |> Message.retag_changeset(attrs, user, opts)
        |> Repo.update()
        |> MessageCaching.update_cached_message()

      with {:ok, _message} <- ret,
           true <- opts[:retag_children] do
        new_opts = put_in(opts, [:retag_children], false)

        MessageHelpers.with_subtree(message, fn msg ->
          if msg.message_id != message.message_id,
            do: retag_message(msg, attrs, user, new_opts)
        end)
      end

      ret
    end)
  end

  defp subtree_message_ids(msg), do: [msg.message_id | Enum.map(msg.messages, &subtree_message_ids/1)]

  @doc """
  Deletes a Message.

  ## Examples

      iex> delete_message(message)
      {:ok, %Message{}}

      iex> delete_message(message)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_message(Cforum.Users.User.t(), Message.t(), String.t() | nil) ::
          {:error, Ecto.Changeset.t()} | {:ok, Cforum.Messages.Message.t()}
  def delete_message(user, %Message{} = message, reason \\ nil) do
    message_ids =
      message
      |> subtree_message_ids()
      |> List.flatten()
      |> tl()

    System.audited("destroy", user, fn ->
      ret =
        message
        |> Ecto.Changeset.change(%{deleted: true, flags: Map.put(message.flags, "reason", reason)})
        |> Repo.update()

      with {:ok, message} <- ret do
        from(m in Message,
          where: m.message_id in ^message_ids,
          update: [set: [deleted: true, flags: fragment("? - 'reason'", m.flags)]]
        )
        |> Repo.update_all([])

        {:ok, message}
      end
    end)
    |> ThreadCaching.refresh_cached_thread()
    |> unnotify_user(message_ids)
    |> unindex_messages([message.message_id | message_ids])
  end

  defp unindex_messages({:ok, msg}, ids) do
    UnindexMessageJob.enqueue(ids)
    {:ok, msg}
  end

  defp unindex_messages(val, _), do: val

  @doc """
  Restores a Message.

  ## Examples

      iex> restore_message(message)
      {:ok, %Message{}}

      iex> restore_message(message)
      {:error, %Ecto.Changeset{}}

  """
  @spec restore_message(Cforum.Users.User.t(), Cforum.Messages.Message.t()) :: {:ok, Message.t()}
  def restore_message(user, %Message{} = message) do
    message_ids =
      message
      |> subtree_message_ids()
      |> List.flatten()

    System.audited("restore", user, fn ->
      from(m in Message,
        where: m.message_id in ^message_ids,
        update: [set: [deleted: false, flags: fragment("? - 'reason'", m.flags)]]
      )
      |> Repo.update_all([])

      {:ok, message}
    end)
    |> ThreadCaching.refresh_cached_thread()
    |> index_messages(message_ids)
  end

  defp index_messages({:ok, msg}, ids) do
    MessageIndexerJob.enqueue(ids)
    {:ok, msg}
  end

  defp index_messages(val, _), do: val

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking message changes.

  ## Examples

      iex> change_message(message)
      %Ecto.Changeset{source: %Message{}}

  """
  @spec change_message(Cforum.Messages.Message.t(), nil | Cforum.Users.User.t(), [Cforum.Forums.Forum.t()], map()) ::
          Ecto.Changeset.t()
  def change_message(%Message{} = message, user, visible_forums, attrs \\ %{}) do
    Message.new_or_update_changeset(message, attrs, user, visible_forums)
  end

  @doc """
  Returns a changeset for a new message.

  ## Parameters

  message: the parent message (`nil` if none present)
  user: the current user
  visible_forums: the forums visible to the current user
  opts: options for generating the changeset, valid keys are
        `strip_signature`, `greeting`, `farewell`, `signature`, `email`,
        `homepage`, `author`, `quote`, `std_replacement`

  ## Examples

      iex> new_message_changeset(%Message{}, %User{}, [%Forum{}], [])
      %Ecto.Changeset{}
  """
  @spec new_message_changeset(nil | Message.t(), nil | Cforum.Users.User.t(), [Cforum.Forums.Forum.t()], map, keyword) ::
          Ecto.Changeset.t()
  def new_message_changeset(message, user, visible_forums, params, opts \\ []) do
    opts =
      Keyword.merge(
        [
          strip_signature: true,
          greeting: nil,
          farewell: nil,
          signature: nil,
          email: nil,
          homepage: nil,
          author: nil,
          quote: true,
          std_replacement: "all"
        ],
        opts
      )

    cnt =
      if opts[:quote],
        do: Helpers.attribute_value(message, :content, ""),
        else: ""

    content =
      cnt
      |> CompositionHelpers.quote_from_content(opts[:strip_signature])
      |> CompositionHelpers.maybe_add_greeting(
        opts[:greeting],
        Helpers.attribute_value(message, :author),
        opts[:std_replacement]
      )
      |> CompositionHelpers.maybe_add_farewell(opts[:farewell])
      |> CompositionHelpers.maybe_add_signature(opts[:signature])

    changeset =
      %Message{
        author: opts[:author],
        email: opts[:email],
        homepage: opts[:homepage],
        subject: Helpers.attribute_value(message, :subject),
        problematic_site: Helpers.attribute_value(message, :problematic_site),
        content: content
      }
      |> change_message(user, visible_forums, params)

    if Helpers.blank?(Ecto.Changeset.get_field(changeset, :tags)),
      do: Ecto.Changeset.put_assoc(changeset, :tags, Helpers.attribute_value(message, :tags, [])),
      else: changeset
  end

  @doc """
  Increases the `downvotes` field of a message by `by`. `by` can also be
  negative.

  ## Examples

      iex> score_down_message(%Message{})
      {1, nil}
  """
  @spec score_down_message(%Message{}, integer()) :: any()
  def score_down_message(message, by \\ 1) do
    ret =
      from(
        msg in Message,
        where: msg.message_id == ^message.message_id,
        update: [inc: [downvotes: ^by]]
      )
      |> Repo.update_all([])

    RescoreMessageJob.enqueue(message)
    MessageCaching.update_cached_message(message, fn msg -> %Message{msg | downvotes: msg.downvotes + by} end)

    notify_users(%Message{message | downvotes: message.downvotes + by}, :score)

    ret
  end

  @doc """
  Increases the `upvotes` field of a message by `by`. `by` can also be
  negative.

  ## Examples

      iex> score_up_message(%Message{})
      {1, nil}
  """
  @spec score_up_message(%Message{}, integer()) :: any()
  def score_up_message(message, by \\ 1) do
    ret =
      from(
        msg in Message,
        where: msg.message_id == ^message.message_id,
        update: [inc: [upvotes: ^by]]
      )
      |> Repo.update_all([])

    RescoreMessageJob.enqueue(message)
    MessageCaching.update_cached_message(message, fn msg -> %Message{msg | upvotes: msg.upvotes + by} end)

    notify_users(%Message{message | upvotes: message.upvotes + by}, :score)

    ret
  end

  @doc """
  Accepts a message (sets the `"accept"` flag value to `"yes"`) if not yet
  accepted. Credits `points` points to the author of the message.

  - `message` is the message to accept
  - `user` is the current user (relevant for the audit log)
  - `points` are the points to credit to the user

  ## Examples

      iex> accept_message(%Message{}, %User{}, 15)
      {:ok, _}
  """
  @spec accept_message(Message.t(), Cforum.Users.User.t(), non_neg_integer()) :: any
  def accept_message(message, user, points)
  def accept_message(%Message{flags: %{"accepted" => "yes"}}, _, _), do: nil

  def accept_message(message, user, points) do
    Repo.transaction(fn ->
      Message
      |> where(message_id: ^message.message_id)
      |> Repo.update_all(set: [flags: Map.put(message.flags, "accepted", "yes")])

      MessageCaching.update_cached_message(message, &%Message{&1 | flags: Map.put(&1.flags, "accepted", "yes")})

      case maybe_give_accept_score(message, user, points) do
        nil ->
          RescoreMessageJob.enqueue(message)
          :ok

        {:ok, _} ->
          RescoreMessageJob.enqueue(message)
          :ok

        _ ->
          Repo.rollback(nil)
      end
    end)
  end

  defp maybe_give_accept_score(%Message{user_id: nil}, _, _), do: nil

  defp maybe_give_accept_score(message, user, points) do
    System.audited("accepted-score", user, fn ->
      Scores.create_score(%{message_id: message.message_id, user_id: message.user_id, value: points})
    end)
  end

  @doc """
  Removes the accepted flag from a message

  - `message` is the message to accept
  - `user` is the current user (relevant for the audit log)

  ## Examples

      iex> unaccept_message(%Message{}, %User{})
      {:ok, _}
  """
  @spec unaccept_message(Message.t(), Cforum.Users.User.t()) :: any
  def unaccept_message(message, user) do
    Repo.transaction(fn ->
      message = %Message{message | flags: Map.delete(message.flags, "accepted")}

      Message
      |> where(message_id: ^message.message_id)
      |> Repo.update_all(set: [flags: message.flags])

      MessageCaching.update_cached_message(message, &%Message{&1 | flags: Map.delete(&1.flags, "accepted")})

      case maybe_take_accept_score(message, user) do
        nil ->
          RescoreMessageJob.enqueue(message)
          {:ok, message}

        {:ok, msg} ->
          RescoreMessageJob.enqueue(message)
          {:ok, msg}

        _ ->
          Repo.rollback(nil)
      end
    end)
  end

  defp maybe_take_accept_score(%Message{user_id: nil}, _), do: nil

  defp maybe_take_accept_score(message, user) do
    System.audited("accepted-no-unscore", user, fn ->
      Scores.delete_score_by_message_id_and_user_id(message.message_id, message.user_id)
      {:ok, message}
    end)
  end

  @doc """
  Sets a flag to the message and its subtree

  - `message` is the message to flag
  - `flag` is the flag to set
  - `value` is the value to set the flag to

  ## Examples

      iex> flag_message_subtree(%Message{}, "no-answer", "yes")
      {:ok, %Message{}}
  """
  @spec flag_message_subtree(Message.t(), String.t(), String.t()) :: {:ok, Message.t()}
  def flag_message_subtree(message, flag, value) do
    message_ids =
      message
      |> subtree_message_ids()
      |> List.flatten()

    from(m in Message,
      where: m.message_id in ^message_ids,
      update: [set: [flags: fragment("jsonb_set(?, ?, ?)", m.flags, [^flag], ^value)]]
    )
    |> Repo.update_all([])

    {:ok, message}
  end

  @doc """
  Removes a flag from the message and its subtree

  - `message` is the message to flag
  - `flag` is the flag to set

  ## Examples

      iex> unflag_message_subtree(%Message{}, "no-answer")
      {:ok, %Message{}}
  """
  @spec unflag_message_subtree(Message.t(), String.t()) :: {:ok, Message.t()}
  def unflag_message_subtree(message, flag) do
    message_ids =
      message
      |> subtree_message_ids()
      |> List.flatten()

    from(m in Message,
      where: m.message_id in ^message_ids,
      update: [set: [flags: fragment("? - ?", m.flags, ^flag)]]
    )
    |> Repo.update_all([])

    {:ok, message}
  end

  @doc """
  Sets a the no answer flag of the message and its subtree to yes

  - `user` the current user
  - `message` is the message to flag
  - `type` is the no answer type, one of `"no-answer"` or `"no-answer-admin"`

  ## Examples

      iex> flag_no_answer(%User{}, %Message{})
      {:ok, %Message{}}
  """
  @spec flag_no_answer(Cforum.Users.User.t(), Message.t(), String.t() | nil, String.t()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def flag_no_answer(user, message, reason, type \\ "no-answer-admin") when type in ~w(no-answer-admin no-answer) do
    System.audited("flag-no-answer", user, fn ->
      message_ids =
        message
        |> subtree_message_ids()
        |> List.flatten()
        |> tl()

      new_flags =
        message.flags
        |> Map.put("reason", reason)
        |> Map.put(type, "yes")

      ret =
        message
        |> Ecto.Changeset.change(%{flags: new_flags})
        |> Repo.update()

      with {:ok, message} <- ret do
        from(m in Message,
          where: m.message_id in ^message_ids,
          update: [set: [flags: fragment("jsonb_set(? - 'reason', ?, '\"yes\"')", m.flags, ^[type])]]
        )
        |> Repo.update_all([])

        {:ok, message}
      end
    end)
    |> ThreadCaching.refresh_cached_thread()
  end

  @doc """
  Removes a the no answer flag of the message and its subtree

  - `user` the current user
  - `message` is the message to flag
  - `type` is the no answer type, one of `"no-answer"` or `"no-answer-admin"`

  ## Examples

      iex> unflag_no_answer(%User{}, %Message{})
      {:ok, %Message{}}
  """
  @spec unflag_no_answer(Cforum.Users.User.t(), Message.t(), [String.t()]) :: {:ok, Message.t()}
  def unflag_no_answer(user, message, types \\ ["no-answer-admin", "no-answer"]) do
    System.audited("unflag-no-answer", user, fn ->
      Enum.each(types, fn type ->
        {:ok, _} = unflag_message_subtree(message, type)
      end)

      new_flags = Map.drop(message.flags, ["reason" | types])

      message
      |> Ecto.Changeset.change(%{flags: new_flags})
      |> Repo.update()

      {:ok, message}
    end)
    |> ThreadCaching.refresh_cached_thread()
  end

  @spec content_with_presentational_filters(nil | maybe_improper_list | map, Message.t(), :content | :excerpt) ::
          String.t()
  def content_with_presentational_filters(assigns, message, part) do
    message
    |> Mentions.mentions_markup(assigns[:current_user])
    |> Map.get(part)
  end

  defp notify_users(message_or_changeset, thread_or_score, notify \\ true)
  defp notify_users(val, _, false), do: val
  defp notify_users({:error, changeset}, _, _), do: {:error, changeset}

  defp notify_users({:ok, message}, thread, _) do
    NotifyUsersMessageJob.enqueue(thread, message, "message")
    {:ok, message}
  end

  defp notify_users(message, :score, _) do
    CforumWeb.Endpoint.broadcast!("forum:#{message.forum_id}", "message_rescored", %{
      message_id: message.message_id,
      score: MessageHelpers.score(message),
      score_str: MessageHelpers.score_str(message),
      upvotes: message.upvotes,
      downvotes: message.downvotes
    })
  end
end
