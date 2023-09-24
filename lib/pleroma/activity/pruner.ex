defmodule Pleroma.Activity.Pruner do
  @moduledoc """
  Prunes activities from the database.
  """

  alias Pleroma.Activity
  alias Pleroma.Repo
  import Ecto.Query

  def prune_deletes, do: prune("Delete")
  def prune_undos, do: prune("Undo")
  def prune_removes, do: prune("Remove")

  defp prune(activity_type) do
    before_time = cutoff()

    from(a in Activity,
      where: fragment("?->>'type' = ?", a.data, ^activity_type) and a.inserted_at < ^before_time
    )
    |> Repo.delete_all(timeout: :infinity)
  end

  defp cutoff do
    deadline = Pleroma.Config.get([:instance, :remote_post_retention_days])

    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-(deadline * 86_400))
  end
end
