# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.AntiHellthreadPolicy do
  @moduledoc "Notify local users upon remote block."
  @behaviour Pleroma.Web.ActivityPub.MRF

  alias Pleroma.User
  alias Pleroma.Web.CommonAPI

  defp is_block_or_unblock(%{"type" => "Block", "object" => object}),
    do: {true, "blocked", object}

  defp is_block_or_unblock(%{
         "type" => "Undo",
         "object" => %{"type" => "Block", "object" => object}
       }),
       do: {true, "unblocked", object}

  defp is_block_or_unblock(_), do: {false, nil, nil}

  defp is_remote_or_displaying_local?(%User{local: false}), do: true

  defp is_remote_or_displaying_local?(_),
    do: Pleroma.Config.get([:mrf_anti_hellthread_policy, :display_local])

  @impl true
  def filter(message) do

    with {true, action, object} <- is_block_or_unblock(message),
         %User{} = actor <- User.get_cached_by_ap_id(message["actor"]),
         %User{} = recipient <- User.get_cached_by_ap_id(object),
         true <- recipient.local,
         true <- is_remote_or_displaying_local?(actor),
         false <- User.blocks_user?(recipient, actor) do
      bot_user = Pleroma.Config.get([:mrf_anti_hellthread_policy, :user])

      _reply =
        CommonAPI.post(User.get_by_nickname(bot_user), %{
          status: "@" <> recipient.nickname <> " you have been " <> action <> " by @" <> actor.nickname,
          visibility: "direct"
        })
    end

    {:ok, message}
  end

  @impl true
  def describe, do: {:ok, %{}}
end
