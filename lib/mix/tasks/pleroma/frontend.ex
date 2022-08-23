# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Frontend do
  use Mix.Task

  import Mix.Pleroma

  @shortdoc "Manages bundled Pleroma frontends"

  @moduledoc File.read!("docs/administration/CLI_tasks/frontend.md")

  def run(["list-available" | _args]) do
    start_pleroma()

    shell_info("These frontends are available, in <name>/<ref> format:")

    Pleroma.Frontend.list()
    |> Enum.map(fn desc ->
      shell_info("  #{desc["name"]}/#{desc["ref"]}" <> (if desc["installed"], do: " (installed)", else: ""))
    end)

    shell_info("\nUse `mix pleroma.frontend install <name> [--ref <ref>]` to install.")
  end

  def run(["install", "none" | _args]) do
    shell_info("Skipping frontend installation because none was requested")
    "none"
  end

  def run(["install", frontend | args]) do
    start_pleroma()

    {options, [], []} =
      OptionParser.parse(
        args,
        strict: [
          ref: :string,
          static_dir: :string,
          build_url: :string,
          build_dir: :string,
          file: :string
        ]
      )

    Pleroma.Frontend.install(frontend, options)
  end
end
