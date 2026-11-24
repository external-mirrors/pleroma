# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.ActorStatusView do
  use Pleroma.Web, :view

  require Pleroma.Constants

  alias Pleroma.Activity
  alias Pleroma.HTML
  alias Pleroma.Object
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.MastodonAPI.StatusView

  def render("show.json", %{activity: %Activity{data: %{"type" => "Create"}} = activity} = opts) do
    object = Object.normalize(activity, fetch: false)
    content = object.data["content"] |> HTML.strip_tags() || ""
    raw_content = object.data["content"] |> HTML.filter_tags() || ""

    user = CommonAPI.get_user(activity.data["actor"])

    %{
      id: activity.id,
      account: AccountView.render("show.json", %{user: user, for: opts[:for]}),
      actor_status: %{
        content: content,
        raw_content: raw_content,
        emojis: StatusView.build_emojis(object.data["emoji"])
      }
    }
  end

  def render("show.json", %{activity: %Activity{data: %{"type" => "Delete"}} = activity} = opts) do
    user = CommonAPI.get_user(activity.data["actor"])

    %{
      id: activity.id,
      account: AccountView.render("show.json", %{user: user, for: opts[:for]}),
      actor_status: %{
        content: "",
        raw_content: "",
        emojis: []
      }
    }
  end
end
