# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Pipeline do
  alias Pleroma.Activity
  alias Pleroma.Config
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Utils
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.MRF
  alias Pleroma.Web.ActivityPub.ObjectValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.DeleteValidator
  alias Pleroma.Web.ActivityPub.SideEffects
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.Federator

  defp side_effects, do: Config.get([:pipeline, :side_effects], SideEffects)
  defp federator, do: Config.get([:pipeline, :federator], Federator)
  defp object_validator, do: Config.get([:pipeline, :object_validator], ObjectValidator)
  defp mrf, do: Config.get([:pipeline, :mrf], MRF)
  defp activity_pub, do: Config.get([:pipeline, :activity_pub], ActivityPub)
  defp config, do: Config.get([:pipeline, :config], Config)

  @type results :: {:ok, Activity.t() | Object.t(), keyword()}
  @type errors :: {:error | :reject, any()}

  # Delete errors must roll back persistence and database-backed side effects.
  @spec common_pipeline(map(), keyword()) :: results() | errors()
  def common_pipeline(object, meta) do
    transaction = fn ->
      with :ok <- lock_delete_target(object) do
        object
        |> rollback_delete_error(do_common_pipeline(object, meta))
      else
        {:error, _} = error -> Repo.rollback(error)
      end
    end

    case run_transaction(object, transaction) do
      {:ok, {:ok, activity, meta}} ->
        side_effects().handle_after_transaction(meta)
        {:ok, activity, meta}

      {:ok, {:error, _} = error} ->
        return_error(object, error)

      {:ok, {:reject, _} = error} ->
        return_error(object, error)

      {:error, {:error, _} = error} ->
        return_error(object, error)

      {:error, {:reject, _} = error} ->
        return_error(object, error)

      {:error, e} ->
        invalidate_delete_caches(object)
        {:error, e}
    end
  end

  defp run_transaction(object, transaction) do
    try do
      Repo.transaction(transaction, Utils.query_timeout())
    rescue
      exception ->
        invalidate_delete_caches(object)
        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        invalidate_delete_caches(object)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp rollback_delete_error(%{"type" => "Delete"}, {:error, _} = error),
    do: Repo.rollback(error)

  defp rollback_delete_error(%{"type" => "Delete"}, {:reject, _} = error),
    do: Repo.rollback(error)

  defp rollback_delete_error(_object, result), do: result

  def do_common_pipeline(%{__struct__: _}, _meta), do: {:error, :is_struct}

  def do_common_pipeline(message, meta) do
    with {_, {:ok, validated_message, meta}} <-
           {:validate, object_validator().validate(message, meta)},
         message <- validated_message,
         {_, {:ok, message, meta}} <- {:mrf, mrf().pipeline_filter(message, meta)},
         {_, :ok} <-
           {:delete_identity, ensure_delete_identity(validated_message, message)},
         {_, :continue} <-
           {:idempotent_delete, maybe_skip_idempotent_delete(message, meta)},
         {_, {:ok, message, meta}} <- {:persist, activity_pub().persist(message, meta)},
         {_, {:ok, message, meta}} <- {:side_effects, side_effects().handle(message, meta)},
         {_, {:ok, _}} <- {:federation, maybe_federate(message, meta)} do
      {:ok, message, meta}
    else
      {:mrf, {:reject, message, _}} -> {:reject, message}
      {:delete_identity, {:error, reason}} -> {:error, reason}
      {:idempotent_delete, {:ok, activity, meta}} -> {:ok, activity, meta}
      {:idempotent_delete, {:error, reason}} -> {:error, reason}
      e -> {:error, e}
    end
  end

  defp maybe_skip_idempotent_delete(message, meta) do
    case Keyword.get(meta, :delete_target) do
      %{state: :tombstone_duplicate, existing_delete: %Activity{} = activity} ->
        if activity.data["id"] == message["id"] and activity.data["actor"] == message["actor"] do
          {:ok, activity, meta}
        else
          {:error, :already_deleted}
        end

      _ ->
        :continue
    end
  end

  defp lock_delete_target(%{"type" => "Delete", "object" => object}) do
    case object_id(object) do
      object_id when is_binary(object_id) ->
        case Repo.query(
               "SELECT pg_advisory_xact_lock(hashtext('pleroma:delete'), hashtext($1))",
               [object_id]
             ) do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        :ok
    end
  end

  defp lock_delete_target(_), do: :ok

  defp ensure_delete_identity(
         %{"type" => "Delete", "id" => id, "actor" => actor, "object" => object},
         %{
           "type" => "Delete",
           "id" => id,
           "actor" => actor,
           "object" => filtered_object
         }
       ) do
    if object_id(object) == object_id(filtered_object) do
      :ok
    else
      {:error, :delete_identity_changed}
    end
  end

  defp ensure_delete_identity(%{"type" => "Delete"}, _),
    do: {:error, :delete_identity_changed}

  defp ensure_delete_identity(_, %{"type" => "Delete"}),
    do: {:error, :delete_identity_changed}

  defp ensure_delete_identity(_, _), do: :ok

  defp object_id(%{"id" => object_id}), do: object_id
  defp object_id(object_id) when is_binary(object_id), do: object_id
  defp object_id(_), do: nil

  defp return_error(object, {:error, {stage, _reason}} = error)
       when stage in [:side_effects, :federation] do
    invalidate_delete_caches(object)
    error
  end

  defp return_error(_object, error), do: error

  defp invalidate_delete_caches(%{"type" => "Delete", "object" => object}) do
    object
    |> object_id()
    |> invalidate_delete_target_caches()
  end

  defp invalidate_delete_caches(_), do: :ok

  defp invalidate_delete_target_caches(object_id) when is_binary(object_id) do
    case Object.get_by_ap_id(object_id) do
      %Object{} = object ->
        Object.invalid_object_cache(object)
        invalidate_target_actor_cache(object_id, object.data["actor"])
        invalidate_object_cache(object.data["inReplyTo"])
        invalidate_object_cache(object.data["quoteUrl"])

      nil ->
        invalidate_user_cache(object_id)
        invalidate_create_actor_cache(object_id)
    end
  end

  defp invalidate_delete_target_caches(_), do: :ok

  defp invalidate_user_cache(ap_id) when is_binary(ap_id) do
    case User.get_by_ap_id(ap_id) do
      %User{} = user -> User.invalidate_cache(user)
      _ -> :ok
    end
  end

  defp invalidate_user_cache(_), do: :ok

  defp invalidate_target_actor_cache(_object_id, actor) when is_binary(actor),
    do: invalidate_user_cache(actor)

  defp invalidate_target_actor_cache(object_id, _actor),
    do: invalidate_create_actor_cache(object_id)

  defp invalidate_create_actor_cache(object_id) do
    case DeleteValidator.get_create_by_object_ap_id(object_id) do
      %Activity{data: %{"actor" => actor}} -> invalidate_user_cache(actor)
      _ -> :ok
    end
  end

  defp invalidate_object_cache(ap_id) when is_binary(ap_id) do
    case Object.get_by_ap_id(ap_id) do
      %Object{} = object -> Object.invalid_object_cache(object)
      _ -> :ok
    end
  end

  defp invalidate_object_cache(_), do: :ok

  defp maybe_federate(%Object{}, _), do: {:ok, :not_federated}

  defp maybe_federate(%Activity{} = activity, meta) do
    with {:ok, local} <- Keyword.fetch(meta, :local) do
      do_not_federate = meta[:do_not_federate] || !config().get([:instance, :federating])

      if !do_not_federate and local and not Visibility.local_public?(activity) do
        activity =
          if object = Keyword.get(meta, :object_data) do
            %{activity | data: Map.put(activity.data, "object", object)}
          else
            activity
          end

        federator().publish(activity)
        {:ok, :federated}
      else
        {:ok, :not_federated}
      end
    else
      _e -> {:error, :badarg}
    end
  end
end
