defmodule Cforum.ReadMessages do
  use Appsignal.Instrumentation.Decorators

  import Ecto.Query, warn: false

  alias Cforum.Repo
  alias Cforum.Messages.Message
  alias Cforum.ReadMessages.ReadMessage
  alias Cforum.InvisibleThreads.InvisibleThread

  @doc """
  Marks a single message or list of messages as read

  ## Parameters

  user: the current user
  message: the message to mark read, **or**
  messages: the list of messages to mark read

  ## Examples

      iex> mark_messages_read(%User{}, %Message{})
  """
  def mark_messages_read(nil, _), do: nil
  def mark_messages_read(user, message) when not is_list(message), do: mark_messages_read(user, [message])

  @decorate transaction()
  def mark_messages_read(user, messages) do
    messages = Enum.reject(messages, & &1.attribs[:is_read])

    for msg <- messages do
      ret =
        %ReadMessage{}
        |> ReadMessage.changeset(%{message_id: msg.message_id, user_id: user.user_id})
        |> Repo.insert()

      case ret do
        {:ok, rm} ->
          rm

        {:error, _} ->
          nil
      end
    end
    |> Enum.filter(&(!is_nil(&1)))
    |> notify_user(user)
  end

  @decorate transaction()
  def mark_messages_unread(user, messages) do
    message_ids = Enum.map(messages, & &1.message_id)

    from(rm in ReadMessage, where: rm.user_id == ^user.user_id, where: rm.message_id in ^message_ids)
    |> Repo.delete_all()

    notify_user(messages, user, "message_marked_unread")
  end

  defp notify_user(read_messages, user, type \\ "message_marked_read") do
    message_ids = Enum.map(read_messages, & &1.message_id)
    CforumWeb.Endpoint.broadcast("users:#{user.user_id}", type, %{"message_ids" => message_ids})
    read_messages
  end

  @doc """
  Counts the number of unread threads and messages for a user. Returns a tuple
  `{number of unread threads, number of unread messages}`. A thread is counted
  as unread if it contains unread messages; so a return value of `{1, 5}` means
  five unread messages in one thread.

  ## Examples

      iex> count_unread_messages(%User{})
      {1, 5}
  """
  def count_unread_messages(user, visible_forums)
  def count_unread_messages(nil, _), do: {0, 0}

  def count_unread_messages(user, visible_forums) do
    forum_ids = Enum.map(visible_forums, & &1.forum_id)

    from(
      msg in Message,
      select: {fragment("COUNT(DISTINCT ?)", msg.thread_id), count()},
      inner_join: thr in assoc(msg, :thread),
      left_join: rm in ReadMessage,
      on: rm.message_id == msg.message_id and rm.user_id == ^user.user_id,
      left_join: inv in InvisibleThread,
      on: inv.thread_id == thr.thread_id and inv.user_id == ^user.user_id,
      where: msg.deleted == false and thr.archived == false and msg.draft == false,
      where: is_nil(rm.message_id) and is_nil(inv.thread_id),
      where: msg.forum_id in ^forum_ids
    )
    |> Repo.one()
  end
end
