defmodule Pleroma.Activity.Pruner do
  @moduledoc """
  Prunes activities from the database.
  """

  alias Pleroma.Activity
  alias Pleroma.Repo
  import Ecto.Query

  def prune_deletes do
    before_time = cutoff()

    from(a in Activity,
      where: fragment("?->>'type' = ?", a.data, "Delete") and a.inserted_at < ^before_time
    )
    |> Repo.delete_all(timeout: :infinity)
  end

  def prune_undos do
    before_time = cutoff()

    from(a in Activity,
      where: fragment("?->>'type' = ?", a.data, "Undo") and a.inserted_at < ^before_time
    )
    |> Repo.delete_all(timeout: :infinity)
  end

  def prune_removes do
    before_time = cutoff()

    from(a in Activity,
      where: fragment("?->>'type' = ?", a.data, "Remove") and a.inserted_at < ^before_time
    )
    |> Repo.delete_all(timeout: :infinity)
  end

  defp cutoff do
    deadline = Pleroma.Config.get([:instance, :remote_post_retention_days])

    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-(deadline * 86_400))
  end
end
