# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.ScrobbleView do
  use Pleroma.Web, :view

  require Pleroma.Constants

  alias Pleroma.Activity
  alias Pleroma.HTML
  alias Pleroma.Object
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.CommonAPI.Utils
  alias Pleroma.Web.MastodonAPI.AccountView

  def render("show.json", %{scrobble: %Activity{data: %{"type" => "Listen"}} = scrobble} = _opts) do
    scrobble_schema_skeleton(scrobble)
  end

  def render("show.json", %{activity: %Activity{data: %{"type" => "Listen"}} = activity} = opts) do
    user = CommonAPI.get_user(activity.data["actor"])

    scrobble_schema_skeleton(activity)
    |> Map.put(:account, AccountView.render("show.json", %{user: user, for: opts[:for]}))
  end

  def render("index.json", opts) do
    safe_render_many(opts.activities, __MODULE__, "show.json", opts)
  end

  defp scrobble_schema_skeleton(%Activity{data: %{"type" => "Listen"}} = scrobble) do
    object = Object.normalize(scrobble, fetch: false)
    created_at = Utils.to_masto_date(scrobble.data["published"])

    %{
      id: scrobble.id,
      created_at: created_at,
      title: object.data["title"] |> HTML.strip_tags(),
      artist: object.data["artist"] |> HTML.strip_tags(),
      album: object.data["album"] |> HTML.strip_tags(),
      length: object.data["length"]
    }
  end
end
