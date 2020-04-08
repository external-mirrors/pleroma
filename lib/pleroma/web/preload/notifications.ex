# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Preload.Providers.Notifications do
  alias Pleroma.Web.MastodonAPI.MastodonAPI
  alias Pleroma.Web.MastodonAPI.NotificationView
  alias Pleroma.Web.Preload.Providers.Provider

  @behaviour Provider

  @notification_url :"api/v1/notifications"
  @impl Provider

  def generate_terms(auth_user, _) do
    Map.put(%{}, @notification_url, notifications(auth_user))
  end

  defp notifications(nil), do: %{}

  defp notifications(auth_user) do
    notifications = MastodonAPI.get_notifications(auth_user, %{})
    NotificationView.render("index.json", notifications: notifications, for: auth_user)
  end
end
