# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Retention.CursorTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Retention.Cursor

  describe "id_at/1" do
    test "orders activity ids around the given time" do
      time = ~N[2025-01-01 00:00:00]
      before = Cursor.id_at(NaiveDateTime.add(time, -1))
      later = Cursor.id_at(NaiveDateTime.add(time, 1))

      assert Cursor.after?(Cursor.id_at(time), before)
      assert Cursor.after?(later, Cursor.id_at(time))
      refute Cursor.after?(before, later)
    end
  end

  test "after?/2 treats a missing position as the very beginning" do
    assert Cursor.after?(Cursor.id_at(~N[2020-01-01 00:00:00]), nil)
  end

  test "put/2 and get/1 persist a position per name" do
    id = Cursor.id_at(~N[2025-01-01 00:00:00])
    assert :ok = Cursor.put("test", id)
    assert Cursor.get("test") == id
    assert is_nil(Cursor.get("other"))
  end
end
