# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.ConversationView do
  use Pleroma.Web, :view

  import Ecto.Query

  alias Pleroma.Activity
  alias Pleroma.Repo
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.MastodonAPI.StatusView

  def render("participations.json", %{participations: participations, for: user}) do
    participations = Repo.preload(participations, conversation: [], recipients: [])

    last_activity_ids =
      participations
      |> Enum.map(& &1.last_activity_id)
      |> Enum.reject(&is_nil/1)

    activities =
      if last_activity_ids != [] do
        Activity
        |> where([a], a.id in ^last_activity_ids)
        |> Activity.with_preloaded_object()
        |> Repo.all()
        |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    safe_render_many(participations, __MODULE__, "participation.json", %{
      as: :participation,
      for: user,
      activities: activities
    })
  end

  def render("participation.json", %{participation: participation, for: user} = opts) do
    participation =
      if Ecto.assoc_loaded?(participation.conversation) and
           Ecto.assoc_loaded?(participation.recipients) do
        participation
      else
        Repo.preload(participation, conversation: [], recipients: [])
      end

    last_activity_id =
      with nil <- participation.last_activity_id do
        ActivityPub.fetch_latest_direct_activity_id_for_context(
          participation.conversation.ap_id,
          %{
            user: user,
            blocking_user: user
          }
        )
      end

    activity =
      if last_activity_id do
        get_in(opts, [:activities, last_activity_id]) ||
          Activity.get_by_id_with_object(last_activity_id)
      end

    # Conversations return all users except the current user,
    # except when the current user is the only participant
    users =
      if length(participation.recipients) > 1 do
        Enum.reject(participation.recipients, &(&1.id == user.id))
      else
        participation.recipients
      end

    %{
      id: participation.id |> to_string(),
      accounts: render(AccountView, "index.json", users: users, for: user),
      unread: !participation.read,
      last_status:
        render(StatusView, "show.json",
          activity: activity,
          direct_conversation_id: participation.id,
          for: user
        )
    }
  end
end
