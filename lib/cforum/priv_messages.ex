defmodule Cforum.PrivMessages do
  @moduledoc """
  The boundary for the PrivMessages system.
  """

  use Appsignal.Instrumentation.Decorators
  import Ecto.Query, warn: false

  alias Cforum.Helpers
  alias Cforum.Repo
  alias Cforum.PrivMessages.PrivMessage
  alias Cforum.Users.User
  alias Cforum.Caching
  alias Cforum.Helpers.CompositionHelpers

  def discard_pm_cache({:ok, pm}) do
    Caching.del(:cforum, "notifications/unread/#{pm.owner_id}")
    {:ok, pm}
  end

  def discard_pm_cache(%User{} = user), do: Caching.del(:cforum, "notifications/unread/#{user.user_id}")
  def discard_pm_cache(val), do: val

  @doc """
  Returns the list of priv_messages of a user.

  ## Parameters

  - user: the owner of the desired messages
  - query_params: an option list containing a `order` and a `limit` option,
    describing the sort order and the offset/limit

  ## Examples

      iex> list_priv_messages(%Cforum.Users.User{})
      [%PrivMessage{}, ...]

  """
  def list_priv_messages(user, query_params \\ [order: nil, limit: nil, messages_order: nil]) do
    from(
      pm in PrivMessage,
      where:
        pm.owner_id == ^user.user_id and
          pm.priv_message_id in fragment(
            "SELECT MIN(priv_message_id) FROM priv_messages WHERE owner_id = ? GROUP BY thread_id",
            ^user.user_id
          ),
      preload: [:recipient, :sender]
    )
    |> Cforum.PagingApi.set_limit(query_params[:limit])
    |> Cforum.OrderApi.set_ordering(query_params[:order], desc: :created_at)
    |> order_by(desc: :priv_message_id)
    |> Repo.all()
    |> Repo.preload(
      messages:
        {from(pm in PrivMessage, where: pm.owner_id == ^user.user_id)
         |> order_messages(query_params[:messages_order]), [:recipient, :sender]}
    )
  end

  def list_unread_priv_messages(user, query_params \\ [order: nil, limit: nil]) do
    from(
      pm in PrivMessage,
      where: pm.owner_id == ^user.user_id and pm.is_read == false,
      preload: [:recipient, :sender]
    )
    |> Cforum.PagingApi.set_limit(query_params[:limit])
    |> Cforum.OrderApi.set_ordering(query_params[:order], desc: :created_at)
    |> Repo.all()
  end

  @doc """
  Returns the list of the newest priv_messages of a user for each thread.

  ## Parameters

  - user: the owner of the desired messages
  - query_params: an option list containing a `order` and a `limit` option,
    describing the sort order and the offset/limit

  ## Examples

      iex> list_priv_messages(%Cforum.Users.User{})
      [%PrivMessage{}, ...]

  """
  def list_newest_priv_messages_of_each_thread(user, query_params \\ [order: nil, limit: nil, messages_order: nil]) do
    from(
      pm in PrivMessage,
      select: %PrivMessage{
        pm
        | count:
            fragment(
              "SELECT COUNT(*) FROM priv_messages WHERE thread_id = ? AND owner_id = ?",
              pm.thread_id,
              ^user.user_id
            )
      },
      where:
        pm.owner_id == ^user.user_id and
          pm.priv_message_id in fragment(
            "SELECT MAX(priv_message_id) FROM priv_messages WHERE owner_id = ? GROUP BY thread_id",
            ^user.user_id
          ),
      preload: [:recipient, :sender]
    )
    |> maybe_filter_author(query_params[:author], user)
    |> Cforum.PagingApi.set_limit(query_params[:limit])
    |> order_threadlist(query_params[:order], user)
    |> order_by(desc: :priv_message_id)
    |> Repo.all()
  end

  defp maybe_filter_author(q, v, _) when v == "" or is_nil(v), do: q

  defp maybe_filter_author(q, author, user) do
    from(pm in q,
      where:
        (pm.sender_id == ^user.user_id and pm.recipient_name == ^author) or
          (pm.recipient_id == ^user.user_id and pm.sender_name == ^author)
    )
  end

  defp order_threadlist(q, [{dir, :partner}], user) do
    from(pm in q,
      order_by:
        {^dir,
         fragment(
           "(CASE WHEN ? = ? THEN ? WHEN ? = ? THEN ? END)",
           pm.sender_id,
           ^user.user_id,
           pm.recipient_name,
           pm.recipient_id,
           ^user.user_id,
           pm.sender_name
         )}
    )
  end

  defp order_threadlist(q, col, _), do: Cforum.OrderApi.set_ordering(q, col, desc: :created_at)

  defp order_messages(q, :asc), do: order_by(q, asc: :created_at)
  defp order_messages(q, _), do: order_by(q, desc: :created_at)

  @doc """
  Counts the newest priv_messages of a user of each thread

  ## Parameters

  - user: the owner of the desired messages

  ## Examples

      iex> count_newest_priv_messages_of_each_thread(%Cforum.Users.User{})
      0

  """
  def count_newest_priv_messages_of_each_thread(user, query_params \\ []) do
    from(
      pm in PrivMessage,
      where:
        pm.owner_id == ^user.user_id and
          pm.priv_message_id in fragment(
            "SELECT MAX(priv_message_id) FROM priv_messages WHERE owner_id = ? GROUP BY thread_id",
            ^user.user_id
          ),
      select: count()
    )
    |> maybe_filter_author(query_params[:author], user)
    |> Repo.one()
  end

  @doc """
  Counts the priv_messages of a user

  ## Parameters

  - user: the owner of the desired messages
  - only_unread: count only unread messages if true, count all messages if false

  ## Examples

      iex> count_priv_messages(%Cforum.Users.User{})
      1

      iex> count_priv_messages(%Cforum.Users.User{}, true)
      0

  """
  def count_priv_messages(user, only_unread \\ false)

  def count_priv_messages(user, false) do
    from(pm in PrivMessage, where: pm.owner_id == ^user.user_id, select: count())
    |> Repo.one()
  end

  def count_priv_messages(user, true) do
    Caching.fetch(:cforum, "notifications/unread/#{user.user_id}", fn ->
      from(pm in PrivMessage, where: pm.owner_id == ^user.user_id and pm.is_read == false, select: count())
      |> Repo.one!()
    end)
  end

  @doc """
  Gets a single priv_messages.

  Raises `Ecto.NoResultsError` if the Priv messages does not exist or
  belongs to a different user.

  ## Parameters

  - user: The owner of the priv_message
  - id: The ID of the priv_message

  ## Examples

      iex> get_priv_messages!(%User{}, 123)
      %PrivMessage{}

      iex> get_priv_messages!(%User{}, 456)
      ** (Ecto.NoResultsError)

  """
  def get_priv_message!(user, id) do
    PrivMessage
    |> Repo.get_by!(priv_message_id: id, owner_id: user.user_id)
    |> Repo.preload([:sender, :recipient])
  end

  @doc """
  Gets a whole thread of priv_messages.

  Raises `Ecto.NoResultsError` if the there could no messages be found
  belonging to the user with the specified thread ID

  ## Parameters

  - user: The owner of the priv_message
  - tid: The thread ID
  - query_params: an option list containing a `:messages_order` key,
    describing the sort order of the messages

  ## Examples

      iex> get_priv_message_thread!(%User{}, 123)
      [%PrivMessage{}]

      iex> get_priv_message_thread!(%User{}, 456)
      ** (Ecto.NoResultsError)

  """
  def get_priv_message_thread!(user, tid, query_params \\ [messages_order: nil]) do
    q =
      from(
        pm in PrivMessage,
        where: pm.thread_id == ^tid and pm.owner_id == ^user.user_id,
        preload: [:sender, :recipient]
      )
      |> order_messages(query_params[:messages_order])
      |> order_by(desc: :priv_message_id)

    result = Repo.all(q)

    case result do
      [] -> raise Ecto.NoResultsError, queryable: q
      other -> other
    end
  end

  @doc """
  Creates a priv_messages for both, the owner and the recipient.

  Returns the message copy of the owner on success.

  ## Parameters

  - owner: the owner of the message
  - attrs: the message attributes

  ## Examples

      iex> create_priv_messages(%User{}, %{field: value})
      {:ok, %PrivMessage{}}

      iex> create_priv_messages(%User{}, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_priv_message(owner, attrs \\ %{}) do
    retval =
      Repo.transaction(fn ->
        with {:ok, foreign_pm} <- create_foreign_pm(owner, attrs),
             priv_message <- Repo.get!(PrivMessage, foreign_pm.priv_message_id),
             {:ok, our_pm} <- create_our_pm(owner, attrs, priv_message) do
          {our_pm, priv_message}
        else
          {:error, val} -> Repo.rollback(val)
          val -> Repo.rollback(val)
        end
      end)

    case retval do
      {:ok, {our_pm, foreign_pm}} ->
        discard_pm_cache(%User{user_id: foreign_pm.recipient_id})
        Cforum.Helpers.AsyncHelper.run_async(fn -> notify_user(foreign_pm) end)
        {:ok, our_pm}

      {:error, {:error, val}} ->
        {:error, val}

      val ->
        val
    end
  end

  defp create_foreign_pm(owner, attrs) do
    %PrivMessage{}
    |> PrivMessage.changeset(attrs, owner)
    |> Repo.insert()
  end

  defp create_our_pm(owner, attrs, priv_message) do
    %PrivMessage{
      is_read: true,
      thread_id: priv_message.thread_id
    }
    |> PrivMessage.changeset(attrs, owner, true)
    |> Repo.insert()
  end

  @doc """
  Deletes a PrivMessage.

  ## Examples

      iex> delete_priv_messages(priv_message)
      {:ok, %PrivMessage{}}

      iex> delete_priv_messages(priv_message)
      {:error, %Ecto.Changeset{}}

  """
  def delete_priv_message(%PrivMessage{} = priv_message) do
    priv_message
    |> Repo.delete()
    |> discard_pm_cache()
  end

  def delete_thread(%PrivMessage{} = priv_message) do
    from(pm in PrivMessage,
      where: pm.thread_id == ^priv_message.thread_id,
      where: pm.owner_id == ^priv_message.owner_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking priv_messages changes.

  ## Examples

      iex> change_priv_messages(priv_message)
      %Ecto.Changeset{source: %PrivMessage{}}

  """
  def change_priv_message(%PrivMessage{} = priv_message, attrs \\ %{}) do
    PrivMessage.changeset(priv_message, attrs)
  end

  @doc """
  Returns an tuple of `{%PrivMessage{}, %Ecto.Changeset{}}` for preview purposes.

  ## Examples

      iex> preview_priv_message(params)
      {%PrivMessage{}, %Ecto.Changeset{source: %PrivMessage{}}}

  """
  def preview_priv_message(attrs \\ %{}) do
    changeset = change_priv_message(%PrivMessage{created_at: Timex.now()}, attrs)
    {Ecto.Changeset.apply_changes(changeset), changeset}
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for the purpose of showing a new
  `%PrivMessage{}` form. It contains greeting, farewell, etc of the
  user

  ## Parameters

  - priv_message: the private message struct
  - opts: A keyword list with the keys `:greeting`, `:farewell`,
    `:signature`, `:quote` and `:std_replacement`

  ## Examples

      iex> new_changeset(%PrivMessage, greeting: "Hi {$name},\n\n")
      %Ecto.Changeset{source: %PrivMessage{}}

  """
  def new_changeset(%PrivMessage{} = priv_message, params \\ %{}, opts \\ []) do
    opts =
      Keyword.merge(
        [
          greeting: nil,
          farewell: nil,
          signature: nil,
          quote: true,
          std_replacement: "all"
        ],
        opts
      )

    content =
      ""
      |> CompositionHelpers.maybe_add_greeting(opts[:greeting], opts[:author], opts[:std_replacement])
      |> CompositionHelpers.maybe_add_farewell(opts[:farewell])
      |> CompositionHelpers.maybe_add_signature(opts[:signature])

    change_priv_message(%PrivMessage{priv_message | body: content}, params)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for the purpose of showing an answer
  `%PrivMessage{}` form. It contains greeting, farewell, ... of the
  user, prepends a `"RE: "` to the subject, takes care of quoting, etc

  ## Parameters

  - priv_message: the private message struct
  - parent: the `%PrivMessage{}` we answer to
  - opts: A keyword list with the keys `:greeting`, `:farewell`,
    `:signature`, `:quote` and `:std_replacement`

  ## Examples

      iex> answer_changeset(%PrivMessage{}, %PrivMessage{}, greeting: "Hi {$name},\n\n")
      %Ecto.Changeset{source: %PrivMessage{}}

  """
  def answer_changeset(%PrivMessage{} = priv_message, parent, opts \\ []) do
    opts =
      Keyword.merge(
        [
          strip_signature: true,
          greeting: nil,
          farewell: nil,
          signature: nil,
          quote: true,
          std_replacement: parent.sender.username,
          subject_prefix: "RE: "
        ],
        opts
      )

    cnt =
      if opts[:quote],
        do: Helpers.attribute_value(parent, :body, ""),
        else: ""

    content =
      cnt
      |> CompositionHelpers.quote_from_content(opts[:strip_signature])
      |> CompositionHelpers.maybe_add_greeting(opts[:greeting], parent.sender.username, opts[:std_replacement])
      |> CompositionHelpers.maybe_add_farewell(opts[:farewell])
      |> CompositionHelpers.maybe_add_signature(opts[:signature])

    subject = CompositionHelpers.subject_from_parent(parent.subject, opts[:subject_prefix])

    change_priv_message(priv_message, %{
      subject: subject,
      body: content,
      recipient_id: parent.sender_id,
      thread_id: parent.thread_id
    })
  end

  @doc """
  Marks a priv_message as read or unread

  ## Parameters

  - priv_message: the private message
  - type: either `:unread` for marking a message unread or `:read` for
    marking a message read

  ## Examples

      iex> mark_priv_message(priv_message, :read)
      %PrivMessage{}

  """
  def mark_priv_message(%PrivMessage{} = priv_message, type) when type in [:read, :unread] do
    mark = if type == :unread, do: false, else: true

    priv_message
    |> PrivMessage.mark_changeset(%{is_read: mark})
    |> Repo.update()
    |> discard_pm_cache()
  end

  @doc """
  Returns the name of the partner for a priv_message, so if
  recipient == owner it returns the sender name; if
  recipient != owner, it returns the recpient name

  ## Examples

      iex> partner_name(%PrivMessage{owner_id: 1, recipient_id: 1, sender_name: "Luke"})
      "Luke"

      iex> partner_name(%PrivMessage{owner_id: 1, recipient_id: 2, recipient_name: "Leia"})
      "Leia"

  """
  def partner_name(%PrivMessage{owner_id: oid, recipient_id: rid} = msg) when oid == rid, do: msg.sender_name
  def partner_name(%PrivMessage{} = msg), do: msg.recipient_name

  @doc """
  Returns the user ID of the partner for a priv_message, so
  if recipient == owner it returns the sender; if recipient != owner,
  it returns the recpient

  ## Examples

      iex> partner_id(%PrivMessage{owner_id: 1, recipient_id: 1})
      1

      iex> partner_id(%PrivMessage{owner_id: 1, recipient_id: 2})
      2

  """
  def partner_id(%PrivMessage{owner_id: oid, recipient_id: rid} = msg) when oid == rid, do: msg.sender_id
  def partner_id(%PrivMessage{} = msg), do: msg.recipient_id

  @doc """
  Returns the `%User{}` struct of the partner for a priv_message, so
  if recipient == owner it returns the sender; if recipient != owner,
  it returns the recpient

  ## Examples

      iex> partner(%PrivMessage{owner_id: 1, recipient_id: 1})
      %User{user_id: 1}

      iex> partner(%PrivMessage{owner_id: 1, recipient_id: 2})
      %User{user_id: 2}

  """
  def partner(%PrivMessage{owner_id: oid, recipient_id: rid} = msg) when oid == rid, do: msg.sender
  def partner(%PrivMessage{} = msg), do: msg.recipient

  @doc """
  Notifies the recipient of a priv_message about a new PM if wanted.

  ## Examples

      iex> notify_user(%PrivMessage{})
      true

      iex> partner(%PrivMessage{})
      false

  """
  @decorate transaction(:notify)
  def notify_user(priv_message) do
    priv_message = Repo.preload(priv_message, [:recipient, :sender])

    CforumWeb.Endpoint.broadcast!("users:#{priv_message.recipient_id}", "new_priv_message", %{
      unread: count_priv_messages(priv_message.recipient, true),
      priv_message: priv_message,
      path: CforumWeb.Views.ViewHelpers.Path.mail_thread_path(CforumWeb.Endpoint, :show, priv_message)
    })

    user = Cforum.Users.get_user!(priv_message.recipient_id)

    if Cforum.ConfigManager.uconf(user, "notify_on_new_mail") == "email" do
      Cforum.Jobs.NotificationMailerJob.enqueue_for_pm(priv_message, user)
      true
    else
      false
    end
  end
end
