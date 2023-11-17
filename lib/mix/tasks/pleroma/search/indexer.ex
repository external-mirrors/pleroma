# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Search.Indexer do
  import Mix.Pleroma
  import Ecto.Query

  def run(["index"]) do
    start_pleroma()
    Pleroma.HTML.compile_scrubbers()

    q =
      from(a in Pleroma.Activity,
        limit: 100_000,
        order_by: [desc: :id]
      )

    Pleroma.Repo.transaction(fn ->
      Pleroma.Repo.stream(q, timeout: :infinity)
      |> Stream.each(fn activity ->
        Pleroma.Search.add_to_index(activity)
      end)
      |> Stream.run()
    end)
  end
end
