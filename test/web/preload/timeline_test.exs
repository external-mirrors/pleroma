# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Preload.Providers.TimelineTest do
  use Pleroma.DataCase
  import Pleroma.Factory

  alias Pleroma.Web.Preload.Providers.Timelines
  @public_url :"/api/v1/timelines/public"

  setup do
    user = insert(:user)

    svd_config = Pleroma.Config.get([:restrict_unauthenticated, :timelines])
    on_exit fn ->
      Pleroma.Config.put([:restrict_unauthenticated, :timelines], svd_config)
    end

    {:ok, %{user: user}}
  end

  test "returns nothing when restricted", %{user: user} do
    Pleroma.Config.put([:restrict_unauthenticated, :timelines], %{local: true, federated: true})

    tl_data = Timelines.generate_terms(nil, %{user: user})

    refute Map.has_key?(tl_data, "/api/v1/timelines/public")
  end

  test "returns the timeline when not restricted", %{user: user} do
    Pleroma.Config.put([:restrict_unauthenticated, :timelines, :federated], false)

    tl_data = Timelines.generate_terms(nil, %{user: user})

    assert Map.has_key?(tl_data, @public_url)
  end
end
