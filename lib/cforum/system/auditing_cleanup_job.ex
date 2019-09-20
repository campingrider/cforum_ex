defmodule Cforum.System.AuditingCleanupJob do
  import Ecto.Query, warn: false
  require Logger

  alias Cforum.Repo
  alias Cforum.System.Auditing

  def maintenance do
    Logger.info("Starting auditing cleanup…")

    from(au in Auditing, where: au.created_at < ago(12, "month"))
    |> Repo.delete_all()

    Logger.info("auditing cleanup finished!")
  end
end
