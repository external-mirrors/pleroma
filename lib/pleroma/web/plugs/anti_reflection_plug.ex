# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.AntiReflectionPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.remote_ip in local_ips() do
      conn
      |> put_status(:forbidden)
      |> halt
    else
      conn
    end
  end

  defp local_ips() do
    :net.getifaddrs()
    |> elem(1)
    |> Enum.map(&get_in(&1, [:addr, :addr]))
  end
end
