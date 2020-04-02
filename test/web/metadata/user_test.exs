# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Metadata.Providers.UserTest do
  use Pleroma.DataCase
  import Pleroma.Factory
  alias Pleroma.Web.Metadata.Providers.User

  setup do: clear_config([Pleroma.Web.Metadata, :unfurl_nsfw])

  test "it renders the accounts" do
    user = insert(:user)

    result = User.build_tags(%{user: user})

    %{"acct" => username, "username" => username} =
      case Enum.find(result, nil, &find_tag(&1, "user:account")) do
        {:meta, properties, []} ->
          get_decoded_content(properties)

        _ ->
          %{}
      end
  end

  test "it renders the relationships" do
    user = insert(:user)

    result = User.build_tags(%{user: user})

    [
      %{
        "blocked_by" => false,
        "blocking" => false,
        "showing_reblogs" => true,
        "subscribing" => false
      }
    ] =
      case Enum.find(result, nil, &find_tag(&1, "user:relationships")) do
        {:meta, properties, []} ->
          get_decoded_content(properties)

        _ ->
          %{}
      end
  end

  defp get_decoded_content(props) do
    props
    |> Keyword.get(:content, "")
    |> Jason.decode!()
  end

  defp find_tag(tag, property) do
    with {:meta, properties, []} <- tag,
         prop_name <- Keyword.get(properties, :property, false) do
      String.equivalent?(prop_name, property)
    else
      _ ->
        false
    end
  end
end
