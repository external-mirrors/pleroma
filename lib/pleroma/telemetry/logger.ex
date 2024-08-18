# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Telemetry.Logger do
  @moduledoc "Transforms Pleroma telemetry events to logs"

  require Logger

  @events [
    [:oban, :job, :exception],
    [:pleroma, :activity, :mrf, :filter],
    [:pleroma, :activity, :mrf, :pass],
    [:pleroma, :activity, :mrf, :reject],
    [:pleroma, :activitypub, :inbox],
    [:pleroma, :activitypub, :publisher],
    [:pleroma, :instance, :reachable],
    [:pleroma, :instance, :unreachable],
    [:pleroma, :connection_pool, :client, :add],
    [:pleroma, :connection_pool, :client, :dead],
    [:pleroma, :connection_pool, :provision_failure],
    [:pleroma, :connection_pool, :reclaim, :start],
    [:pleroma, :connection_pool, :reclaim, :stop],
    [:pleroma, :upload, :success],
    [:pleroma, :user, :account, :confirm],
    [:pleroma, :user, :account, :password_reset],
    [:pleroma, :user, :account, :register],
    [:pleroma, :user, :o_auth, :failure],
    [:pleroma, :user, :o_auth, :revoke],
    [:pleroma, :user, :o_auth, :success],
    [:pleroma, :user, :create],
    [:pleroma, :user, :delete],
    [:pleroma, :user, :update],
    [:tesla, :request, :exception],
    [:tesla, :request, :stop]
  ]
  def setup do
    if not Pleroma.Config.get([Pleroma.Telemetry, :phoenix_logs]) do
      Pleroma.Telemetry.disable_phoenix_logs()
    end

    Enum.each(@events, fn event ->
      :telemetry.attach({__MODULE__, event}, event, &__MODULE__.handle_event/4, [])
    end)
  end

  # Passing anonymous functions instead of strings to logger is intentional,
  # that way strings won't be concatenated if the message is going to be thrown
  # out anyway due to higher log level configured

  def handle_event([:oban, :job, :exception], _measure, meta, _) do
    Logger.error(fn ->
      "[Oban] #{meta.worker} error: #{inspect(meta.error)} args: #{inspect(meta.args)}"
    end)
  end

  def handle_event(
        [:pleroma, :connection_pool, :reclaim, :start],
        _measurements,
        %{max_connections: max_connections, reclaim_max: reclaim_max},
        _
      ) do
    Logger.debug(fn ->
      "Connection pool is exhausted (reached #{max_connections} connections). Starting idle connection cleanup to reclaim as much as #{reclaim_max} connections"
    end)
  end

  def handle_event(
        [:pleroma, :connection_pool, :reclaim, :stop],
        %{count: 0},
        _measurements,
        _
      ) do
    Logger.debug(fn ->
      "Connection pool failed to reclaim any connections due to all of them being in use. It will have to drop requests for opening connections to new hosts"
    end)
  end

  def handle_event(
        [:pleroma, :connection_pool, :reclaim, :stop],
        %{count: reclaimed_count},
        _measurements,
        _
      ) do
    Logger.debug(fn -> "Connection pool cleaned up #{reclaimed_count} idle connections" end)
  end

  def handle_event(
        [:pleroma, :connection_pool, :provision_failure],
        _measurements,
        %{opts: [key | _]},
        _
      ) do
    Logger.debug(fn ->
      "Connection pool had to refuse opening a connection to #{key} due to connection limit exhaustion"
    end)
  end

  def handle_event(
        [:pleroma, :connection_pool, :client, :dead],
        _measurements,
        %{client_pid: client_pid, key: key, reason: reason},
        _
      ) do
    Logger.debug(fn ->
      "Pool worker for #{key}: Client #{inspect(client_pid)} died before releasing the connection with #{inspect(reason)}"
    end)
  end

  def handle_event(
        [:pleroma, :connection_pool, :client, :add],
        _measurements,
        %{clients: [_, _ | _] = clients, key: key, protocol: :http},
        _
      ) do
    Logger.debug(fn ->
      "Pool worker for #{key}: #{length(clients)} clients are using an HTTP1 connection at the same time, head-of-line blocking might occur."
    end)
  end

  def handle_event([:pleroma, :connection_pool, :client, :add], _, _, _), do: :ok

  def handle_event(
        [:pleroma, :activitypub, :inbox],
        _measurements,
        %{ap_id: ap_id, type: type},
        _
      ) do
    Logger.info(fn ->
      "Inbox: received #{type} of #{ap_id}"
    end)
  end

  def handle_event(
        [:pleroma, :activity, :mrf, :pass],
        _measurements,
        %{activity: activity, mrf: mrf},
        _
      ) do
    type = activity["type"]
    ap_id = activity["id"]

    Logger.debug(fn ->
      "#{mrf}: passed #{inspect(type)} of #{inspect(ap_id)}"
    end)
  end

  def handle_event(
        [:pleroma, :activity, :mrf, :filter],
        _measurements,
        %{activity: activity, mrf: mrf},
        _
      ) do
    type = activity["type"]
    ap_id = activity["id"]

    Logger.debug(fn ->
      "#{mrf}: filtered #{inspect(type)} of #{inspect(ap_id)}"
    end)
  end

  def handle_event(
        [:pleroma, :activity, :mrf, :reject],
        _measurements,
        %{activity: activity, mrf: mrf, reason: reason},
        _
      ) do
    type = activity["type"]
    ap_id = activity["id"]

    Logger.info(fn ->
      "#{mrf}: rejected #{inspect(type)} of #{inspect(ap_id)}: #{inspect(reason)}"
    end)
  end

  def handle_event(
        [:pleroma, :upload, :success],
        %{size: size, duration: duration} = _measurements,
        %{nickname: nickname, filename: filename},
        _
      ) do
    Logger.info(fn ->
      upload_size = (size / 1_024_000) |> :erlang.float_to_binary(decimals: 2)
      seconds = duration / 1000
      "Upload: #{nickname} uploaded #{filename} [#{upload_size}MB in #{seconds}s]"
    end)
  end

  def handle_event(
        [:pleroma, :user, :create],
        _measurements,
        %{nickname: nickname},
        _
      ) do
    Logger.info(fn ->
      "User: created #{nickname}"
    end)
  end

  def handle_event(
        [:pleroma, :user, :delete],
        _measurements,
        %{nickname: nickname},
        _
      ) do
    Logger.info(fn ->
      "User: deleted #{nickname}"
    end)
  end

  def handle_event(
        [:pleroma, :user, :disable],
        _measurements,
        %{nickname: nickname},
        _
      ) do
    Logger.info(fn ->
      "User: disabled #{nickname}"
    end)
  end

  def handle_event(
        [:pleroma, :user, :update],
        _measurements,
        %{nickname: nickname},
        _
      ) do
    Logger.debug(fn ->
      "User: updated #{nickname}"
    end)
  end

  def handle_event(
        [:pleroma, :instance, :reachable],
        _measurements,
        %{instance: instance},
        _
      ) do
    unreachable_since = get_in(instance, [Access.key(:unreachable_since)]) || "UNDEFINED"

    Logger.info(fn ->
      "Instance: #{instance.host} is set reachable (was unreachable since: #{unreachable_since})"
    end)
  end

  def handle_event(
        [:pleroma, :instance, :unreachable],
        _measurements,
        %{instance: instance},
        _
      ) do
    Logger.info(fn ->
      "Instance: #{instance.host} is set unreachable"
    end)
  end

  def handle_event(
        [:pleroma, :user, :o_auth, :failure],
        _measurements,
        %{ip: ip, nickname: name},
        _
      ) do
    Logger.error(fn ->
      "OAuth: authentication failure for #{name} from #{ip}"
    end)
  end

  def handle_event(
        [:pleroma, :user, :o_auth, :revoke],
        _measurements,
        %{ip: ip, nickname: name},
        _
      ) do
    Logger.info(fn ->
      "OAuth: token revoked for #{name} from #{ip}"
    end)
  end

  def handle_event(
        [:pleroma, :user, :o_auth, :success],
        _measurements,
        %{ip: ip, nickname: name},
        _
      ) do
    Logger.info(fn ->
      "OAuth: authentication success for #{name} from #{ip}"
    end)
  end

  def handle_event(
        [:pleroma, :user, :account, :confirm],
        _measurements,
        %{user: user},
        _
      ) do
    Logger.info(fn ->
      "Account: #{user.nickname} account confirmed"
    end)
  end

  def handle_event(
        [:pleroma, :user, :account, :password_reset],
        _measurements,
        %{for: for, ip: ip},
        _
      ) do
    Logger.info(fn ->
      "Account: password reset requested for #{for} from #{ip}"
    end)
  end

  def handle_event(
        [:pleroma, :user, :account, :register],
        _measurements,
        %{ip: ip, user: user},
        _
      ) do
    Logger.info(fn ->
      "Account: #{user.nickname} registered from #{ip}"
    end)
  end

  def handle_event(
        [:pleroma, :activitypub, :publisher],
        %{sum: sum},
        %{nickname: nickname, type: type},
        _
      ) do
    Logger.info(fn ->
      "Publisher: delivering #{type} for #{nickname} to #{sum} inboxes"
    end)
  end

  def handle_event([:tesla, :request, :exception], _measure, meta, _) do
    Logger.error(fn -> "Pleroma.HTTP exception #{inspect(meta.stacktrace)}" end)
  end

  def handle_event(
        [:tesla, :request, :stop],
        _measurements,
        %{env: %Tesla.Env{method: method, url: url}, error: error} = _meta,
        _
      ) do
    Logger.warning(fn ->
      "Pleroma.HTTP :#{method} failed for #{url} with error #{inspect(error)}"
    end)
  end

  def handle_event(
        [:tesla, :request, :stop],
        _measurements,
        %{env: %Tesla.Env{method: method, status: status, url: url}} = _meta,
        _
      ) do
    cond do
      status in 200..299 ->
        :ok

      true ->
        Logger.warning(fn -> "Pleroma.HTTP :#{method} status #{status} for #{url}" end)
    end
  end

  # Catchall
  def handle_event(event, measurements, metadata, _) do
    Logger.debug(fn ->
      "Unhandled telemetry event #{inspect(event)} with measurements #{inspect(measurements)} and metadata #{inspect(metadata)}"
    end)

    :ok
  end
end
