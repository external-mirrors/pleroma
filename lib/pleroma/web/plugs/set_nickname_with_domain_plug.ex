# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.SetNicknameWithDomainPlug do
  @moduledoc """
  Qualifies the nickname param with the alternative domain the request was
  made to, so that `/users/bob` on `example.org` resolves to `bob@example.org`.
  """

  use Pleroma.Web, :plug

  alias Pleroma.Domain

  def init(opts), do: opts

  @impl true
  def perform(%{assigns: %{domain: %Domain{} = domain}, params: params} = conn, opts) do
    key = Keyword.get(opts, :key, "nickname")

    case Map.get(params, key) do
      nickname when is_binary(nickname) ->
        if String.contains?(nickname, "@") do
          conn
        else
          %{conn | params: Map.put(params, key, nickname <> "@" <> domain.domain)}
        end

      _ ->
        conn
    end
  end

  def perform(conn, _), do: conn
end
