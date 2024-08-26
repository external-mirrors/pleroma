# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.Policy do
  @type legacy_return :: {:ok | :reject, map()} | {:filter, map()}
  @type return :: {:pass, map()} | {:filter, map()} | {:reject, %{activity: map(), reason: any()}}
  @callback filter(Pleroma.Activity.t()) :: legacy_return() | return()
  @callback describe() :: {:ok | :error, map()}
  @callback config_description() :: %{
              optional(:children) => [map()],
              key: atom(),
              related_policy: String.t(),
              label: String.t(),
              description: String.t()
            }
  @callback history_awareness() :: :auto | :manual
  @optional_callbacks config_description: 0, history_awareness: 0
end
