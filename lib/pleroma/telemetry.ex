# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Telemetry do
  @phoenix_handlers %{
    [:phoenix, :endpoint, :start] => &Phoenix.Logger.phoenix_endpoint_start/4,
    [:phoenix, :endpoint, :stop] => &Phoenix.Logger.phoenix_endpoint_stop/4,
    [:phoenix, :router_dispatch, :start] => &Phoenix.Logger.phoenix_router_dispatch_start/4,
    [:phoenix, :error_rendered] => &Phoenix.Logger.phoenix_error_rendered/4,
    [:phoenix, :socket_connected] => &Phoenix.Logger.phoenix_socket_connected/4,
    [:phoenix, :channel_joined] => &Phoenix.Logger.phoenix_channel_joined/4,
    [:phoenix, :channel_handled_in] => &Phoenix.Logger.phoenix_channel_handled_in/4
  }

  @live_view_handlers %{
    [:phoenix, :live_view, :mount, :start] => &Phoenix.LiveView.Logger.lv_mount_start/4,
    [:phoenix, :live_view, :mount, :stop] => &Phoenix.LiveView.Logger.lv_mount_stop/4,
    [:phoenix, :live_view, :handle_params, :start] =>
      &Phoenix.LiveView.Logger.lv_handle_params_start/4,
    [:phoenix, :live_view, :handle_params, :stop] =>
      &Phoenix.LiveView.Logger.lv_handle_params_stop/4,
    [:phoenix, :live_view, :handle_event, :start] =>
      &Phoenix.LiveView.Logger.lv_handle_event_start/4,
    [:phoenix, :live_view, :handle_event, :stop] =>
      &Phoenix.LiveView.Logger.lv_handle_event_stop/4,
    [:phoenix, :live_component, :handle_event, :start] =>
      &Phoenix.LiveView.Logger.lc_handle_event_start/4,
    [:phoenix, :live_component, :handle_event, :stop] =>
      &Phoenix.LiveView.Logger.lc_handle_event_stop/4
  }

  def disable_phoenix_logs() do
    :telemetry.list_handlers([])
    |> Enum.filter(fn x ->
      match?(%{id: {Phoenix.Logger, _}}, x) or match?(%{id: {Phoenix.LiveView.Logger, _}}, x)
    end)
    |> Enum.map(& &1.id)
    |> Enum.each(&:telemetry.detach(&1))

    :ok
  end

  def enable_phoenix_logs() do
    for {key, fun} <- @phoenix_handlers do
      :telemetry.attach({Phoenix.Logger, key}, key, fun, :ok)
    end

    for {key, fun} <- @live_view_handlers do
      :telemetry.attach({Phoenix.LiveView.Logger, key}, key, fun, :ok)
    end

    :ok
  end
end
