# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.FlagValidationTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Web.ActivityPub.Builder
  alias Pleroma.Web.ActivityPub.ObjectValidator
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  setup do
    reporter = insert(:user)
    reported = insert(:user)
    {:ok, post} = CommonAPI.post(reported, %{status: "bad post"})

    {:ok, flag_data, _meta} =
      Builder.flag(%{
        actor: reporter,
        context: Utils.generate_context_id(),
        account: reported,
        statuses: [post],
        content: "",
        rules: ["1"]
      })

    %{flag_data: flag_data, reporter: reporter, reported: reported}
  end

  test "it validates a report and keeps the reported statuses", %{
    flag_data: flag_data,
    reported: reported
  } do
    assert {:ok, flag, _meta} = ObjectValidator.validate(flag_data, [])

    assert flag["type"] == "Flag"
    assert flag["state"] == "open"
    assert flag["content"] == ""
    assert flag["rules"] == ["1"]
    assert flag["cc"] == [reported.ap_id]
    assert {:ok, _, _} = DateTime.from_iso8601(flag["published"])
    assert [reported_ap_id, %{"type" => "Note", "id" => _}] = flag["object"]
    assert reported_ap_id == reported.ap_id
  end

  test "it does not address the reported account when the report is not forwarded", %{
    reporter: reporter,
    reported: reported
  } do
    {:ok, flag_data, _meta} =
      Builder.flag(%{
        actor: reporter,
        context: Utils.generate_context_id(),
        account: reported,
        statuses: [],
        content: "",
        forward: false
      })

    assert {:ok, flag, _meta} = ObjectValidator.validate(flag_data, [])
    assert flag["cc"] == []
    assert flag["object"] == [reported.ap_id]
  end

  test "it requires the actor to exist", %{flag_data: flag_data} do
    flag_data = Map.put(flag_data, "actor", "https://example.com/users/nobody")

    assert {:error, _} = ObjectValidator.validate(flag_data, [])
  end

  test "it rejects reports without reported objects", %{flag_data: flag_data} do
    assert {:error, _} = ObjectValidator.validate(Map.put(flag_data, "object", []), [])
    assert {:error, _} = ObjectValidator.validate(Map.put(flag_data, "object", [1]), [])
  end
end
