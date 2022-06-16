# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.BrapForUkrainePolicy do
	require Logger
	require Pleroma.Constants
	alias Pleroma.User
	@behaviour Pleroma.Web.ActivityPub.MRF

	@impl true

	def filter(
		%{
			"type" => "Create",
			"to" => mto,
			"cc" => mcc,
			"actor" => mactor,
                        "object" => object
		} = message
	) do
		host = URI.parse(mactor).authority
		if host == "bae.st" do
			if Enum.member?(mto, Pleroma.Constants.as_public()) do
				mcc = mcc ++ ["https://masochi.st/users/e"]
				object = object |> Map.put("cc", mcc)
				message = message  |> Map.put("cc", mcc) |> Map.put("object", object)
				{:ok, message}
			else
				{:ok, message}
			end
		else
			{:ok, message}
		end
	end

	@impl true
	def filter(message), do: {:ok, message}
  @impl true
  def describe, do: {:ok, %{}}
end
