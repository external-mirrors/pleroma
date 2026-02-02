# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Fedbox do
  use Mix.Task

  @shortdoc "Runs federation-in-a-box smoke tests (Docker)"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [keep: :boolean])

    ensure_executable!("docker")

    project_root = Mix.Project.project_file() |> Path.dirname() |> Path.expand()
    compose_file = Path.join(project_root, "docker/federation/compose.yml")

    unless File.exists?(compose_file) do
      Mix.raise("fedbox compose file not found: #{compose_file}")
    end

    Mix.shell().info("Starting fedbox containers...")

    status =
      try do
        case docker_compose(["-f", compose_file, "up", "-d", "--build"]) do
          0 ->
            Mix.shell().info("Running fedbox tests...")

            docker_compose([
              "-f",
              compose_file,
              "--profile",
              "fedtest",
              "run",
              "--rm",
              "--build",
              "fedtest"
            ])

          status ->
            status
        end
      after
        unless opts[:keep] do
          Mix.shell().info("Cleaning up fedbox containers...")
          _ = docker_compose(["-f", compose_file, "down", "-v"])
        end
      end

    if status != 0 do
      System.halt(status)
    end
  end

  defp docker_compose(args) when is_list(args) do
    {_, status} =
      System.cmd("docker", ["compose" | args], into: IO.stream(:stdio, :line))

    status
  end

  defp ensure_executable!(exe) when is_binary(exe) do
    case System.find_executable(exe) do
      nil -> Mix.raise("#{exe} not found in PATH")
      _path -> :ok
    end
  end
end
