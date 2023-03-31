# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Finger.Server do
  use GenServer
  require Logger

  def start_link(_) do
    config = Pleroma.Config.get(:finger, [])
    ip = Keyword.get(config, :ip, {0, 0, 0, 0})
    port = Keyword.get(config, :port, 1079)

    if Keyword.get(config, :enabled, false) do
      GenServer.start_link(__MODULE__, [ip, port], [])
    else
      Logger.info("Finger server disabled")
      :ignore
    end
  end

  def init([ip, port]) do
    Logger.info("Starting finger server on #{port}")

    :ranch.start_listener(
      :finger,
      100,
      :ranch_tcp,
      [ip: ip, port: port],
      __MODULE__.ProtocolHandler,
      []
    )

    {:ok, %{ip: ip, port: port}}
  end
end

defmodule Pleroma.Finger.Server.ProtocolHandler do
  alias Pleroma.Activity
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Visibility

  def start_link(ref, socket, transport, opts) do
    pid = spawn_link(__MODULE__, :init, [ref, socket, transport, opts])
    {:ok, pid}
  end

  def init(ref, socket, transport, [] = _Opts) do
    :ok = :ranch.accept_ack(ref)
    loop(socket, transport)
  end

  def response(username) do
    with %User{pinned_objects: pinned} <- User.get_by_nickname(username),
         {:empty, false} <- {:empty, match?([], pinned)},
         object =
           Enum.to_list(pinned) |> Enum.map(fn {object, _date} -> object end) |> List.last(),
         {_, %Activity{} = activity} <-
           {:activity, Activity.get_create_by_object_ap_id_with_object(object)},
         {_, true} <- {:public?, Visibility.is_public?(activity)} do
      timestamp =
        activity.data["published"]
        |> DateTime.from_iso8601()
        |> elem(1)
        |> Calendar.strftime("%Y-%m-%d %H:%M:%S")

      content =
        activity.object.data["content"]
        |> strip_html

      """
      #{content}
      ---------------------------------------------------------------------
      When this .plan was written: #{timestamp}
      Original URL: #{activity.data["object"]}
      Powered by Pleroma https://pleroma.social
      """
    else
      _ -> "Sorry, #{username} does not have a .plan"
    end
  end

  def loop(socket, transport) do
    case transport.recv(socket, 0, 5000) do
      {:ok, data} ->
        username = String.trim_trailing(data, "\r\n")
        transport.send(socket, response(username))
        :ok = transport.close(socket)

      _ ->
        :ok = transport.close(socket)
    end
  end

  defp strip_html(text) do
    result =
      text
      |> String.replace(~r/<li>/, "\\g{1}- ", global: true)
      |> String.replace(
        ~r/<\/?\s?br>|<\/\s?p>|<\/\s?li>|<\/\s?div>|<\/\s?h.>/,
        "\\g{1}\n\r",
        global: true
      )
      |> FastSanitize.strip_tags()
      |> elem(1)
      |> HtmlEntities.decode()

    result
  end
end
