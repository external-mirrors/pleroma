# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Preload.Providers.TimelineTest do
  use Pleroma.DataCase
  alias Pleroma.Web.Preload.Providers.Timelines

  setup do: {:ok, Timelines.generate_terms()}

  test "returns nothing when restricted" do
    Pleroma.Config.put([:restrict_unauthenticated, :timelines], %{local: true, federated: true})

    %{"/api/v1/timelines/public": timeline} = Timelines.generate_terms(%{})

    assert timeline == %{}
  end
end
