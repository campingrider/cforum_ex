defmodule Cforum.Tags do
  @moduledoc """
  The boundary for the Forums system.
  """

  import Ecto.Query, warn: false
  alias Cforum.Repo

  alias Cforum.Tags.Tag
  alias Cforum.Tags.Synonym
  alias Cforum.System

  @doc """
  Returns the list of tags.

  ## Examples

      iex> list_tags()
      [%Tag{}, ...]

  """
  @spec list_tags() :: [%Tag{}]
  def list_tags(forums \\ nil)

  def list_tags(nil) do
    from(tag in Tag, order_by: [asc: :tag_name, asc: :tag_id], preload: [:synonyms])
    |> Repo.all()
  end

  def list_tags(forums) do
    forum_ids = Enum.map(forums, & &1.forum_id)

    from(tag in Tag,
      where:
        fragment(
          "EXISTS (SELECT message_tag_id FROM messages_tags a INNER JOIN messages b USING(message_id) WHERE a.tag_id = ? AND b.forum_id = ANY(?))",
          tag.tag_id,
          ^forum_ids
        ),
      order_by: [asc: :tag_name, asc: :tag_id],
      preload: [:synonyms]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single tag.

  Raises `Ecto.NoResultsError` if the Tag does not exist.

  ## Examples

      iex> get_tag!(123)
      %Tag{}

      iex> get_tag!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_tag!(String.t() | integer()) :: %Tag{}
  def get_tag!(id) do
    Tag
    |> Repo.get!(id)
    |> Repo.preload([:synonyms])
  end

  @doc """
  Gets a single tag by its slug.

  Raises `Ecto.NoResultsError` if the Tag does not exist.

  ## Examples

      iex> get_tag_by_slug!("rebellion")
      %Tag{}

      iex> get_tag!("imperium")
      ** (Ecto.NoResultsError)
  """
  @spec get_tag_by_slug!(String.t()) :: %Tag{}
  def get_tag_by_slug!(slug) do
    Tag
    |> Repo.get_by!(slug: slug)
    |> Repo.preload([:synonyms])
  end

  @doc """
  Gets a list of tags identified by tag name.

  ## Arguments

  - `tags`: a list of tag names

  ## Examples

  iex> get_tags(["menschelei", "zu diesem forum"])
  [%Tag{}, %Tag{}]

  """
  @spec get_tags([String.t()]) :: [%Tag{}]
  def get_tags(tags) do
    tags = Enum.map(tags, &String.downcase(&1))

    from(t in Tag,
      inner_join:
        t1 in subquery(
          from(
            tag in Tag,
            select: tag.tag_id,
            left_join: syn in assoc(tag, :synonyms),
            where: fragment("lower(?)", tag.tag_name) in ^tags or fragment("lower(?)", syn.synonym) in ^tags,
            group_by: [tag.tag_id]
          )
        ),
      on: t.tag_id == t1.tag_id,
      order_by: [desc: :tag_name, desc: :tag_id]
    )
    |> Repo.all()
    |> Repo.preload([:synonyms])
  end

  @doc """
  Gets a list of tags identified by their `tag_id`

  ## Arguments

  - `tag_ids`: a list of tag IDs

  ## Examples

  iex> get_tags_by_tag_ids([1, 2, -1])
  [%Tag{}, %Tag{}]

  """
  @spec get_tags_by_ids([String.t() | integer()]) :: %Tag{}
  def get_tags_by_ids(tag_ids) do
    from(
      tag in Tag,
      where: tag.tag_id in ^tag_ids,
      order_by: [asc: :tag_name, asc: :tag_id]
    )
    |> Repo.all()
    |> Repo.preload([:synonyms])
  end

  @doc """
  Creates a tag.

  ## Examples

      iex> create_tag(%{field: value})
      {:ok, %Tag{}}

      iex> create_tag(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_tag(%Cforum.Users.User{}, map()) :: {:ok, %Tag{}} | {:error, Ecto.Changeset.t()}
  def create_tag(current_user, attrs \\ %{}) do
    System.audited("create", current_user, fn ->
      %Tag{}
      |> Tag.changeset(attrs)
      |> Repo.insert()
    end)
  end

  @doc """
  Updates a tag.

  ## Examples

      iex> update_tag(tag, %{field: new_value})
      {:ok, %Tag{}}

      iex> update_tag(tag, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_tag(%Cforum.Users.User{}, %Tag{}, map()) :: {:ok, %Tag{}} | {:error, Ecto.Changeset.t()}
  def update_tag(current_user, %Tag{} = tag, attrs) do
    with {:ok, tag} <-
           System.audited("update", current_user, fn ->
             tag
             |> Tag.changeset(attrs)
             |> Repo.update()
           end) do
      Cachex.clear(:cforum)
      {:ok, tag}
    end
  end

  @doc """
  Deletes a Tag.

  ## Examples

      iex> delete_tag(tag)
      {:ok, %Tag{}}

      iex> delete_tag(tag)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_tag(%Cforum.Users.User{}, %Tag{}) :: {:ok, %Tag{}}
  def delete_tag(current_user, %Tag{} = tag) do
    with {:ok, tag} <- System.audited("destroy", current_user, fn -> Repo.delete(tag) end) do
      Cachex.clear(:cforum)
      {:ok, tag}
    end
  end

  @doc """
  Merges two tags so that all messages with belong to the tag
  `old_tag` now belong to the tag `new_tag`. It also adds the old tag
  as a synonym to the new tag.

  ## Examples

      iex> merge_tag(%Tag{}, %Tag{})
      {:ok, %Tag{}}

  """
  @spec merge_tag(%Cforum.Users.User{}, %Tag{}, %Tag{}) :: {:ok, %Tag{}} | {:error, any}
  def merge_tag(_current_user, %Tag{tag_id: tag_id}, %Tag{tag_id: tag_id}),
    do: {:error, :same_tag}

  def merge_tag(current_user, %Tag{} = old_tag, %Tag{} = new_tag) do
    System.audited("merge", current_user, fn ->
      from(mtag in "messages_tags", where: mtag.tag_id == ^old_tag.tag_id)
      |> Repo.update_all(set: [tag_id: new_tag.tag_id])

      from(syn in Synonym, where: syn.tag_id == ^old_tag.tag_id)
      |> Repo.update_all(set: [tag_id: new_tag.tag_id])

      with {:ok, %Synonym{}} <- create_tag_synonym(current_user, new_tag, %{synonym: old_tag.tag_name}),
           {:ok, %Tag{}} <- Repo.delete(old_tag),
           tag = %Tag{} = get_tag!(new_tag.tag_id) do
        Cachex.clear(:cforum)
        {:ok, tag}
      else
        _ ->
          Repo.rollback(nil)
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking tag changes.

  ## Examples

      iex> change_tag(tag)
      %Ecto.Changeset{source: %Tag{}}

  """
  @spec change_tag(%Tag{}) :: Ecto.Changeset.t()
  def change_tag(%Tag{} = tag) do
    Tag.changeset(tag, %{})
  end

  @doc """
  Returns the list of tag synonyms for a tag.

  ## Examples

      iex> list_tag_synonyms(%Tag{})
      [%Synonym{}, ...]

  """
  def list_tag_synonyms(tag) do
    case tag.synonyms do
      %Ecto.Association.NotLoaded{} ->
        from(tag_synonym in Synonym, where: tag_synonym.tag_id == ^tag.tag_id)
        |> Repo.all()

      synonyms ->
        synonyms
    end
  end

  @doc """
  Gets a single tag synonym of a tag.

  Raises `Ecto.NoResultsError` if the Tag does not exist.

  ## Examples

      iex> get_tag_synonym!(%Tag{}, 123)
      %Synonym{}

      iex> get_tag!(%Tag{}, 456)
      ** (Ecto.NoResultsError)

  """
  def get_tag_synonym!(%Tag{} = tag, id), do: Repo.get_by!(Synonym, tag_synonym_id: id, tag_id: tag.tag_id)

  @doc """
  Creates a tag synonym for the given `tag`.

  ## Examples

      iex> create_tag_synonym(%Tag{}, %{synonym: value})
      {:ok, %Synonym{}}

      iex> create_tag(%Tag{}, %{synonym: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  def create_tag_synonym(current_user, %Tag{} = tag, attrs \\ %{}) do
    System.audited("create", current_user, fn ->
      %Synonym{}
      |> Synonym.changeset(tag, attrs)
      |> Repo.insert()
    end)
  end

  @doc """
  Updates a tag synonym.

  ## Examples

      iex> update_tag_synonym(%Tag{}, synonym, %{field: new_value})
      {:ok, %Synonym{}}

      iex> update_tag_synonym(%Tag{}, synonym, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_tag_synonym(current_user, %Tag{} = tag, %Synonym{} = synonym, attrs) do
    System.audited("update", current_user, fn ->
      synonym
      |> Synonym.changeset(tag, attrs)
      |> Repo.update()
    end)
  end

  @doc """
  Deletes a Tag synonym.

  ## Examples

      iex> delete_tag_synonym(synonym)
      {:ok, %Synonym{}}

      iex> delete_tag_synonym(synonym)
      {:error, %Ecto.Changeset{}}

  """
  def delete_tag_synonym(current_user, %Synonym{} = synonym) do
    System.audited("destroy", current_user, fn ->
      Repo.delete(synonym)
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking tag synonym changes.

  ## Examples

      iex> change_tag_synonym(%Tag{}, synonym)
      %Ecto.Changeset{source: %Synonym{}}

  """
  def change_tag_synonym(%Tag{} = tag, %Synonym{} = synonym) do
    Synonym.changeset(synonym, tag, %{})
  end
end
