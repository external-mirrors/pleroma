# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Fedbox do
  use Mix.Task

  @shortdoc "Runs federation-in-a-box smoke tests (Docker)"

  defmodule LineFilter do
    defstruct buffer: "", drop?: nil
  end

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [keep: :boolean, verbose: :boolean])
    verbose? = opts[:verbose] == true

    ensure_executable!("docker")

    project_root = Mix.Project.project_file() |> Path.dirname() |> Path.expand()
    compose_file = Path.join(project_root, "docker/federation/compose.yml")

    unless File.exists?(compose_file) do
      Mix.raise("fedbox compose file not found: #{compose_file}")
    end

    Mix.shell().info("Starting fedbox containers...")

    status =
      try do
        case docker_compose_quiet(
               ["-f", compose_file, "up", "-d", "--build", "--quiet-build", "--quiet-pull"],
               verbose?: verbose?
             ) do
          0 ->
            Mix.shell().info("Building fedbox test runner...")

            case docker_compose_quiet(
                   ["-f", compose_file, "--profile", "fedtest", "build", "-q", "fedtest"],
                   verbose?: verbose?
                 ) do
              0 ->
                Mix.shell().info("Running fedbox tests...")

                stream_opts =
                  if verbose? do
                    []
                  else
                    [filter: :compose_noise]
                  end

                docker_compose_stream(
                  ["-f", compose_file, "--profile", "fedtest", "run", "--rm", "fedtest"],
                  stream_opts
                )

              status ->
                status
            end

          status ->
            status
        end
      after
        unless opts[:keep] do
          Mix.shell().info("Cleaning up fedbox containers...")
          _ = docker_compose_quiet(["-f", compose_file, "down", "-v"], verbose?: verbose?)
        end
      end

    if status != 0 do
      System.halt(status)
    end
  end

  defp docker_compose_quiet(args, opts) when is_list(args) and is_list(opts) do
    if Keyword.get(opts, :verbose?, false) do
      docker_compose_stream(args)
    else
      {output, status} = System.cmd("docker", ["compose" | args], stderr_to_stdout: true)

      if status != 0 do
        IO.binwrite(output)
      end

      status
    end
  end

  defp docker_compose_stream(args, opts \\ []) when is_list(args) and is_list(opts) do
    into =
      case Keyword.get(opts, :filter) do
        :compose_noise ->
          %LineFilter{drop?: &drop_compose_noise?/1}

        _ ->
          IO.stream(:stdio, :line)
      end

    {_, status} =
      System.cmd("docker", ["compose" | args],
        into: into,
        stderr_to_stdout: true
      )

    status
  end

  defp ensure_executable!(exe) when is_binary(exe) do
    case System.find_executable(exe) do
      nil -> Mix.raise("#{exe} not found in PATH")
      _path -> :ok
    end
  end

  defp drop_compose_noise?(line) when is_binary(line) do
    line = String.trim_leading(line)

    String.starts_with?(line, "Container ") or String.starts_with?(line, "Network ") or
      String.starts_with?(line, "Volume ") or
      (String.starts_with?(line, "time=") and String.contains?(line, "No services to build"))
  end
end

defimpl Collectable, for: Mix.Tasks.Pleroma.Fedbox.LineFilter do
  def into(%Mix.Tasks.Pleroma.Fedbox.LineFilter{} = filter) do
    {filter, &collect/2}
  end

  defp collect(%Mix.Tasks.Pleroma.Fedbox.LineFilter{} = filter, {:cont, chunk})
       when is_binary(chunk) do
    buffer = filter.buffer <> chunk
    {lines, rest} = split_lines(buffer)

    Enum.each(lines, fn line ->
      if is_function(filter.drop?, 1) and filter.drop?.(line) do
        :ok
      else
        IO.binwrite(line)
      end
    end)

    %{filter | buffer: rest}
  end

  defp collect(%Mix.Tasks.Pleroma.Fedbox.LineFilter{} = filter, :done) do
    if filter.buffer != "" do
      if is_function(filter.drop?, 1) and filter.drop?.(filter.buffer) do
        :ok
      else
        IO.binwrite(filter.buffer)
      end
    end

    filter
  end

  defp collect(_filter, :halt), do: :ok

  defp split_lines(buffer) when is_binary(buffer) do
    case String.split(buffer, "\n", trim: false) do
      [rest] ->
        {[], rest}

      parts ->
        rest = List.last(parts)

        lines =
          parts
          |> Enum.drop(-1)
          |> Enum.map(&(&1 <> "\n"))

        {lines, rest}
    end
  end
end
