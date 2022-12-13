# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.NotificationTest do
  @moduledoc """
  Send a test notification under the form of a direct message.
  The "From" user must exist and be different from the "To" user.

  For technical reasons, you can't just run this task like an usual one, you need to start the task with a node name and connecting to the running Pleroma instance.

  Firstly, make sure Pleroma is running with a node name; by default it is not.
  To add a node name, you must add the following between `mix` and `phx.server` in whatever you use to start Pleroma: `--sname pleroma-main`.
  Example: `mix --sname pleroma-main phx.server`

  > Warning: While running with a name can be extremely useful for debug purpose, you should disable it as soon you have done you work, unless you are fluent with Elixir, Erlang and BEAM (and make sure the port `4369/TCP` is firewalled!).

  Secondly, to have the mix task to connect to the running Pleroma instance, you also have to give it a node name, it looks almost the same as running Pleroma with a node name: `iex --sname pleroma-mix -S mix pleroma.notification_test ...`

  Thirdly, for the `--node` argument, you have to provide the node name you gave to Pleroma (in the example, that's "pleroma-main"), suffixed by `@<your machine hostname>`.
  If you don't know what your machine hostname is, just run the command `hostname` in a shell and you will get it.

  Example:
  ```
  $ hostname
  wired

  $ iex --sname pleroma-mix -S mix pleroma.notification_test --node="pleroma-main@wired"
  ```

  Wrapping everything together:
  ```
  mix pleroma.notification_test --from="lain" --to="masami" --node="pleroma-main@wired"
  ```
  """

  use Mix.Task
  import Mix.Pleroma

  def run(args) do
    start_pleroma()

    {options, _, _} =
      OptionParser.parse(
        args,
        strict: [
          from: :string,
          to: :string,
          node: :string
        ]
      )

    if Node.self() == :nonode@nohost do
      shell_error("It seems like you didn't start this mix task with a node name.")
      shell_error("Don't worry, run 'mix help pleroma.notification_test' to get help.")
      System.halt()
    end

    if not Keyword.has_key?(options, :from) do
      shell_error("I need '--from' to be set!")
      System.halt()
    end

    if not Keyword.has_key?(options, :to) do
      shell_error("I need '--to' to be set!")
      System.halt()
    end

    if not Keyword.has_key?(options, :node) do
      shell_error("I need '--node' to be set!")
      System.halt()
    end

    node = options |> Keyword.get(:node) |> String.to_atom()

    Node.connect(node)

    # A spawn_link would be much better, but I don't want to run an IEx shell
    # after running this task (hence the `System.halt/1`). Anyway, the spawned
    # function should not run forever, it's a oneshot function, if it fails,
    # it won't last forever, that's not like a GenServer or anything, right?
    Node.spawn(node, Pleroma.Notification, :test_notification, [
      Keyword.get(options, :from),
      Keyword.get(options, :to)
    ])

    shell_info("Done")

    System.halt()
  end
end
