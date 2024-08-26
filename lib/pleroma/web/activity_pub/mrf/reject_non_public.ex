# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.RejectNonPublic do
  @moduledoc "Rejects non-public (followers-only, direct) activities"

  alias Pleroma.Config
  alias Pleroma.User

  @behaviour Pleroma.Web.ActivityPub.MRF.Policy

  require Pleroma.Constants

  @impl true
  def filter(%{"type" => "Create"} = activity) do
    user = User.get_cached_by_ap_id(activity["actor"])

    # Determine visibility
    visibility =
      cond do
        Pleroma.Constants.as_public() in activity["to"] -> "public"
        Pleroma.Constants.as_public() in activity["cc"] -> "unlisted"
        user.follower_address in activity["to"] -> "followers"
        true -> "direct"
      end

    policy = Config.get(:mrf_rejectnonpublic)

    cond do
      visibility in ["public", "unlisted"] ->
        {:pass, activity}

      visibility == "followers" and Keyword.get(policy, :allow_followersonly) ->
        {:pass, activity}

      visibility == "direct" and Keyword.get(policy, :allow_direct) ->
        {:pass, activity}

      true ->
        reason = "visibility: #{visibility}"
        {:reject, %{activity: activity, reason: reason}}
    end
  end

  @impl true
  def filter(activity) do
    {:pass, activity}
  end

  @impl true
  def describe,
    do: {:ok, %{mrf_rejectnonpublic: Config.get(:mrf_rejectnonpublic) |> Map.new()}}

  @impl true
  def config_description do
    %{
      key: :mrf_rejectnonpublic,
      related_policy: "Pleroma.Web.ActivityPub.MRF.RejectNonPublic",
      description: "RejectNonPublic drops posts with non-public visibility settings.",
      label: "MRF Reject Non Public",
      children: [
        %{
          key: :allow_followersonly,
          label: "Allow followers-only",
          type: :boolean,
          description: "Whether to allow followers-only posts"
        },
        %{
          key: :allow_direct,
          type: :boolean,
          description: "Whether to allow direct messages"
        }
      ]
    }
  end
end
