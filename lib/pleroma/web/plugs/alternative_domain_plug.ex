# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.AlternativeDomainPlug do
  @moduledoc """
  Allow access from alternative domains.
  """

  import Plug.Conn

  alias Pleroma.Web.Domains

  def init(options) do
    options
  end

  def call(conn, _options) do
    host =
      conn
      |> get_req_header("host")
      |> List.last()

    available_domains = get_config()

    maybe_match =
      Enum.find(
        available_domains,
        fn item ->
          host == item.host
        end
      )

    base_url =
      if maybe_match do
        %URI{
          host: maybe_match[:host],
          port: maybe_match[:port],
          scheme: maybe_match[:proto]
        }
        |> URI.to_string()
      else
        Pleroma.Web.Endpoint.url()
      end

    Domains.put_current_base(base_url)

    conn
    |> assign(:base_url, base_url)
  end

  defp get_config do
    Pleroma.Config.get([Pleroma.Web.Domains, :alternative_domains], [])
  end
end
