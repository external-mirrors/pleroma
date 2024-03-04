# Pleroma: A lightweight social networking server
# Copyright © 2017-2024 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Migrators.RelayActorTypeMigrator do
  defmodule State do
    use Pleroma.Migrators.Support.BaseMigratorState

    @impl Pleroma.Migrators.Support.BaseMigratorState
    defdelegate data_migration(), to: Pleroma.DataMigration, as: :update_relay_actor_type
  end

  import Ecto.Changeset

  use Pleroma.Migrators.Support.BaseMigrator

  alias Pleroma.Migrators.Support.BaseMigrator
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Builder
  alias Pleroma.Web.ActivityPub.Pipeline

  @doc "This migration updates relay actor type to 'Application'."

  @impl BaseMigrator
  def feature_config_path, do: [:features, :update_relay_actor_type]

  @impl BaseMigrator
  def fault_rate_allowance, do: 0

  @impl BaseMigrator
  def perform do
    # data_migration_id = data_migration_id()
    max_processed_id = get_stat(:max_processed_id, 0)

    Logger.info("Migrating local relay actor types (from uid: #{max_processed_id})...")

    query()
    |> Repo.chunk_stream(1, :batches, timeout: :infinity)
    |> Stream.each(fn users ->
      user_ids = Enum.map(users, fn user -> user.id end)

      results = Enum.map(users, &update_relay_actor_type(&1))

      # failed_ids =
      #   results
      #   |> Enum.filter(&(elem(&1, 0) == :error))
      #   |> Enum.map(&elem(&1, 1))

      chunk_affected_count =
        results
        # |> Enum.filter(&(elem(&1, 0) == :ok))
        |> length()

      # for failed_id <- failed_ids do
      #   _ =
      #     Repo.query(
      #       "INSERT INTO data_migration_failed_ids(data_migration_id, record_id) " <>
      #         "VALUES ($1, $2) ON CONFLICT DO NOTHING;",
      #       [data_migration_id, failed_id]
      #     )
      # end

      # _ =
      #   Repo.query(
      #     "DELETE FROM data_migration_failed_ids " <>
      #       "WHERE data_migration_id = $1 AND record_id = ANY($2)",
      #     [data_migration_id, user_ids -- failed_ids]
      #   )

      max_user_id = Enum.at(user_ids, -1)

      put_stat(:max_processed_id, max_user_id)
      increment_stat(:iteration_processed_count, length(user_ids))
      increment_stat(:processed_count, length(user_ids))
      increment_stat(:failed_count, 0)
      increment_stat(:affected_count, chunk_affected_count)
      put_stat(:records_per_second, records_per_second())
      persist_state()
    end)
    |> Stream.run()
  end

  @impl BaseMigrator
  def query do
    ap_id = Pleroma.Web.ActivityPub.Relay.ap_id()

    from(
      u in User,
      where: u.local == true and u.ap_id == ^ap_id and u.actor_type == "Person"
    )
  end

  @spec update_relay_actor_type(User.t()) :: {:ok | :error, integer()}
  defp update_relay_actor_type(user) do
    with changeset <- cast(user, %{actor_type: "Application"}, [:actor_type]),
         {:ok, unpersisted_user} <- Ecto.Changeset.apply_action(changeset, :update),
         updated_object <-
           Pleroma.Web.ActivityPub.UserView.render("user.json", user: unpersisted_user)
           |> Map.delete("@context"),
         {:ok, update_data, []} <- Builder.update(user, updated_object),
         {:ok, _update, _} <-
           Pipeline.common_pipeline(update_data,
             local: true,
             user_update_changeset: changeset
           ) do
      {:ok, user.id}
    else
      _ -> {:error, user.id}
    end
  end

  @impl BaseMigrator
  def retry_failed do
    data_migration_id = data_migration_id()

    failed_objects_query()
    |> Repo.chunk_stream(100, :one)
    |> Stream.each(fn user ->
      with {res, _} when res != :error <- update_relay_actor_type(user) do
        _ =
          Repo.query(
            "DELETE FROM data_migration_failed_ids " <>
              "WHERE data_migration_id = $1 AND record_id = $2",
            [data_migration_id, user.id]
          )
      end
    end)
    |> Stream.run()

    put_stat(:failed_count, failures_count())
    persist_state()

    force_continue()
  end

  defp failed_objects_query do
    from(u in User)
    |> join(:inner, [u], dmf in fragment("SELECT * FROM data_migration_failed_ids"),
      on: dmf.record_id == u.id
    )
    |> where([_u, dmf], dmf.data_migration_id == ^data_migration_id())
    |> order_by([u], asc: u.id)
  end
end
