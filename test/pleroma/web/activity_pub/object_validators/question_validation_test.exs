# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.QuestionValidationTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Web.ActivityPub.ObjectValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.QuestionValidator
  alias Pleroma.Web.ActivityPub.Utils

  import Pleroma.Factory

  require Pleroma.Constants

  setup do
    clear_config([:instance, :poll_limits], %{
      max_options: 4,
      max_option_chars: 20,
      min_expiration: 60,
      max_expiration: 86_400
    })
  end

  defp option(name, votes \\ 0),
    do: %{"type" => "Note", "name" => name, "replies" => %{"totalItems" => votes}}

  defp in_seconds(seconds),
    do: DateTime.utc_now() |> DateTime.add(seconds) |> DateTime.to_iso8601()

  defp question(extra) do
    Map.merge(
      %{"type" => "Question", "oneOf" => [option("a"), option("b")], "closed" => in_seconds(600)},
      extra
    )
  end

  describe "validate_local_poll/1" do
    test "accepts a poll within the limits" do
      assert :ok = QuestionValidator.validate_local_poll(question(%{}))

      assert :ok =
               QuestionValidator.validate_local_poll(
                 question(%{"oneOf" => nil, "anyOf" => [option("a"), option("b")]})
               )
    end

    test "rejects polls with votes" do
      for extra <- [
            %{"oneOf" => [option("a", 1), option("b")]},
            %{"votersCount" => 3},
            %{"voters" => ["https://remote.example/users/x"]}
          ] do
        assert {:error, "New polls can't have votes"} =
                 QuestionValidator.validate_local_poll(question(extra))
      end
    end

    test "rejects polls over the limits or without an end time" do
      for extra <- [
            %{"oneOf" => Enum.map(1..5, &option("#{&1}"))},
            %{"oneOf" => [option("a"), option(String.duplicate("b", 21))]},
            %{"oneOf" => [option("a"), option("a")]},
            %{"closed" => in_seconds(86_400 * 2)},
            %{"closed" => in_seconds(-10)},
            %{"closed" => nil}
          ] do
        assert {:error, _} = QuestionValidator.validate_local_poll(question(extra))
      end
    end
  end

  test "remote polls are not held to the local limits" do
    user = insert(:user, local: false, ap_id: "https://remote.example/users/pollster")
    id = "https://remote.example/objects/#{Ecto.UUID.generate()}"

    object =
      question(%{
        "id" => id,
        "actor" => user.ap_id,
        "attributedTo" => user.ap_id,
        "to" => [Pleroma.Constants.as_public()],
        "cc" => [],
        "context" => Utils.generate_context_id(),
        "content" => "?",
        "oneOf" => Enum.map(1..10, &option("#{&1}", 5)),
        "votersCount" => 50,
        "closed" => in_seconds(86_400 * 30)
      })

    create = %{
      "id" => id <> "/activity",
      "type" => "Create",
      "actor" => user.ap_id,
      "to" => object["to"],
      "cc" => [],
      "object" => object
    }

    assert {:ok, _, _} = ObjectValidator.validate(create, local: false)
  end
end
