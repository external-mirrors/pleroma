# Pleroma: A lightweight social networking server
# Copyright © 2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.ReleaseVMArgsTest do
  use ExUnit.Case, async: true

  @vm_args_path Path.expand("rel/vm.args.eex", Path.join([__DIR__, "..", ".."]))

  test "release VM args set a finite kernel shutdown_timeout" do
    assert File.exists?(@vm_args_path)

    assert timeout = shutdown_timeout(File.read!(@vm_args_path))
    assert is_integer(timeout)
    assert timeout > 0
  end

  defp shutdown_timeout(content) do
    content
    |> String.split(["\r\n", "\n"])
    |> Enum.map(&strip_comment/1)
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^-\s*kernel\s+shutdown_timeout\s+(\S+)\s*$/, String.trim(line)) do
        [_, value] -> value
        nil -> nil
      end
    end)
    |> case do
      nil ->
        flunk("rel/vm.args.eex does not set -kernel shutdown_timeout")

      "infinity" ->
        flunk("rel/vm.args.eex sets -kernel shutdown_timeout to infinity")

      value ->
        case Integer.parse(value) do
          {timeout, ""} when timeout > 0 ->
            timeout

          _ ->
            flunk("rel/vm.args.eex sets -kernel shutdown_timeout to an invalid value")
        end
    end
  end

  defp strip_comment(line) do
    case String.split(line, "#", parts: 2) do
      [code, _comment] -> code
      [code] -> code
    end
  end
end
