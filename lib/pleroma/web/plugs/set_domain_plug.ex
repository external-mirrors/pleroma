# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.SetDomainPlug do
  @moduledoc """
  Assigns `:domain` when the request was made to one of the alternative
  WebFinger domains. Requests to the instance's own host are left alone.
  """

  use Pleroma.Web, :plug

  alias Pleroma.Domain

  def init(opts), do: opts

  @impl true
  def perform(%{host: host} = conn, _opts) do
    with true <- Pleroma.Config.get([:instance, :multitenancy, :enabled], false),
         false <- host in instance_hosts(),
         %Domain{} = domain <- Domain.cached_get_by_name(host) do
      Plug.Conn.assign(conn, :domain, domain)
    else
      _ -> conn
    end
  end

  defp instance_hosts do
    [
      Pleroma.Config.get([Pleroma.Web.WebFinger, :domain]),
      Pleroma.Web.Endpoint.host()
    ]
  end
end
