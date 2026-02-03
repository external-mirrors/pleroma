defmodule FederationBoxTest do
  use ExUnit.Case, async: false

  import FederationBox

  @moduletag timeout: 240_000

  setup_all do
    {:ok, FederationBox.setup!()}
  end

  test "outgoing follows are accepted (pleroma + mastodon)", ctx do
    follow_and_assert_remote_accept!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_remote_accept!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )
  end

  test "pleroma1 receives posts from followed accounts (pleroma + mastodon)", ctx do
    follow_and_assert_remote_accept!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_remote_accept!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    unique = unique_token()
    bob_text = "fedbox: hello from bob #{unique}"
    carol_text = "fedbox: hello from carol #{unique}"

    _ = create_status!(ctx.pleroma2_base_url, ctx.bob_access_token, bob_text)
    _ = create_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_text)

    wait_until!(
      fn -> home_timeline_contains?(ctx.pleroma1_base_url, ctx.alice_access_token, bob_text) end,
      "pleroma1 received pleroma2 post"
    )

    wait_until!(
      fn -> home_timeline_contains?(ctx.pleroma1_base_url, ctx.alice_access_token, carol_text) end,
      "pleroma1 received mastodon post"
    )
  end

  test "remote receives our posts (pleroma + mastodon)", ctx do
    follow_and_assert_local_accept!(
      ctx.pleroma2_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    unique = unique_token()
    alice_text = "fedbox: hello from alice #{unique}"

    _alice_status = create_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_text)

    wait_until!(
      fn -> home_timeline_contains?(ctx.pleroma2_base_url, ctx.bob_access_token, alice_text) end,
      "pleroma2 received alice post"
    )

    wait_until!(
      fn -> home_timeline_contains?(ctx.mastodon_base_url, ctx.carol_access_token, alice_text) end,
      "mastodon received alice post"
    )
  end

  test "likes: roundtrip with pleroma", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.pleroma2_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    alice_text = "fedbox: like me (pleroma) #{unique}"
    alice_status = create_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    bob_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.pleroma2_base_url, ctx.bob_access_token, alice_uri_variants)
        end,
        "pleroma2 received alice post"
      )

    favourite_status!(ctx.pleroma2_base_url, ctx.bob_access_token, bob_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_status_id)
        favourites_count = Map.get(status, "favourites_count", 0)
        is_integer(favourites_count) and favourites_count > 0
      end,
      "pleroma1 received bob like"
    )

    bob_text = "fedbox: like this (pleroma) #{unique}"
    bob_status = create_status!(ctx.pleroma2_base_url, ctx.bob_access_token, bob_text)
    bob_status_id = bob_status["id"]

    bob_uri_variants =
      bob_status
      |> status_uri()
      |> actor_id_variants()

    alice_view_of_bob_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.pleroma1_base_url, ctx.alice_access_token, bob_uri_variants)
        end,
        "pleroma1 received bob post"
      )

    favourite_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_view_of_bob_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.pleroma2_base_url, ctx.bob_access_token, bob_status_id)
        favourites_count = Map.get(status, "favourites_count", 0)
        is_integer(favourites_count) and favourites_count > 0
      end,
      "pleroma2 received alice like"
    )
  end

  test "likes: roundtrip with mastodon", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    alice_text = "fedbox: like me (mastodon) #{unique}"
    alice_status = create_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    mastodon_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice post"
      )

    favourite_status!(ctx.mastodon_base_url, ctx.carol_access_token, mastodon_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_status_id)
        favourites_count = Map.get(status, "favourites_count", 0)
        is_integer(favourites_count) and favourites_count > 0
      end,
      "pleroma1 received mastodon like"
    )

    carol_text = "fedbox: like this (mastodon) #{unique}"
    carol_status = create_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_text)
    carol_status_id = carol_status["id"]

    carol_uri_variants =
      carol_status
      |> status_uri()
      |> actor_id_variants()

    alice_view_of_carol_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.pleroma1_base_url,
            ctx.alice_access_token,
            carol_uri_variants
          )
        end,
        "pleroma1 received carol post"
      )

    favourite_status!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      alice_view_of_carol_status["id"]
    )

    wait_until!(
      fn ->
        status = fetch_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_status_id)
        favourites_count = Map.get(status, "favourites_count", 0)
        is_integer(favourites_count) and favourites_count > 0
      end,
      "mastodon received alice like"
    )
  end

  test "boosts: roundtrip with pleroma", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.pleroma2_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    alice_text = "fedbox: boost me (pleroma) #{unique}"
    alice_status = create_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    bob_view_of_alice_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.pleroma2_base_url, ctx.bob_access_token, alice_uri_variants)
        end,
        "pleroma2 received alice post"
      )

    _reblog = reblog_status!(ctx.pleroma2_base_url, ctx.bob_access_token, bob_view_of_alice_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_status_id)
        reblogs_count = Map.get(status, "reblogs_count", 0)
        is_integer(reblogs_count) and reblogs_count > 0
      end,
      "pleroma1 received bob boost"
    )

    bob_text = "fedbox: boost this (pleroma) #{unique}"
    bob_status = create_status!(ctx.pleroma2_base_url, ctx.bob_access_token, bob_text)
    bob_status_id = bob_status["id"]

    bob_uri_variants =
      bob_status
      |> status_uri()
      |> actor_id_variants()

    alice_view_of_bob_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.pleroma1_base_url, ctx.alice_access_token, bob_uri_variants)
        end,
        "pleroma1 received bob post"
      )

    _reblog = reblog_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_view_of_bob_status["id"])

    wait_until!(
      fn ->
        status = fetch_status!(ctx.pleroma2_base_url, ctx.bob_access_token, bob_status_id)
        reblogs_count = Map.get(status, "reblogs_count", 0)
        is_integer(reblogs_count) and reblogs_count > 0
      end,
      "pleroma2 received alice boost"
    )
  end

  test "boosts: roundtrip with mastodon", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    alice_text = "fedbox: boost me (mastodon) #{unique}"
    alice_status = create_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    mastodon_view_of_alice_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice post"
      )

    _reblog =
      reblog_status!(
        ctx.mastodon_base_url,
        ctx.carol_access_token,
        mastodon_view_of_alice_status["id"]
      )

    wait_until!(
      fn ->
        status = fetch_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_status_id)
        reblogs_count = Map.get(status, "reblogs_count", 0)
        is_integer(reblogs_count) and reblogs_count > 0
      end,
      "pleroma1 received mastodon boost"
    )

    carol_text = "fedbox: boost this (mastodon) #{unique}"
    carol_status = create_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_text)
    carol_status_id = carol_status["id"]

    carol_uri_variants =
      carol_status
      |> status_uri()
      |> actor_id_variants()

    alice_view_of_carol_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.pleroma1_base_url,
            ctx.alice_access_token,
            carol_uri_variants
          )
        end,
        "pleroma1 received carol post"
      )

    _reblog =
      reblog_status!(
        ctx.pleroma1_base_url,
        ctx.alice_access_token,
        alice_view_of_carol_status["id"]
      )

    wait_until!(
      fn ->
        status = fetch_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_status_id)
        reblogs_count = Map.get(status, "reblogs_count", 0)
        is_integer(reblogs_count) and reblogs_count > 0
      end,
      "mastodon received alice boost"
    )
  end

  test "deletes: roundtrip with pleroma", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      ctx.bob_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.pleroma2_base_url,
      ctx.bob_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.bob_actor_id_variants
    )

    alice_text = "fedbox: delete me (to pleroma) #{unique}"
    alice_status = create_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    bob_view_of_alice_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.pleroma2_base_url, ctx.bob_access_token, alice_uri_variants)
        end,
        "pleroma2 received alice post"
      )

    _ = delete_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_status_id)

    wait_until!(
      fn -> status_gone?(ctx.pleroma2_base_url, ctx.bob_access_token, bob_view_of_alice_status["id"]) end,
      "pleroma2 removed deleted alice post"
    )

    bob_text = "fedbox: delete me (from pleroma) #{unique}"
    bob_status = create_status!(ctx.pleroma2_base_url, ctx.bob_access_token, bob_text)
    bob_status_id = bob_status["id"]

    bob_uri_variants =
      bob_status
      |> status_uri()
      |> actor_id_variants()

    alice_view_of_bob_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(ctx.pleroma1_base_url, ctx.alice_access_token, bob_uri_variants)
        end,
        "pleroma1 received bob post"
      )

    _ = delete_status!(ctx.pleroma2_base_url, ctx.bob_access_token, bob_status_id)

    wait_until!(
      fn -> status_gone?(ctx.pleroma1_base_url, ctx.alice_access_token, alice_view_of_bob_status["id"]) end,
      "pleroma1 removed deleted bob post"
    )
  end

  test "deletes: roundtrip with mastodon", ctx do
    unique = unique_token()

    follow_and_assert_remote_accept!(
      ctx.pleroma1_base_url,
      ctx.alice_access_token,
      ctx.carol_handle,
      ctx.alice_actor_id_variants
    )

    follow_and_assert_local_accept!(
      ctx.mastodon_base_url,
      ctx.carol_access_token,
      ctx.alice_handle,
      ctx.alice_actor_id,
      ctx.carol_actor_id_variants
    )

    alice_text = "fedbox: delete me (to mastodon) #{unique}"
    alice_status = create_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_text)
    alice_status_id = alice_status["id"]

    alice_uri_variants =
      alice_status
      |> status_uri()
      |> actor_id_variants()

    mastodon_view_of_alice_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.mastodon_base_url,
            ctx.carol_access_token,
            alice_uri_variants
          )
        end,
        "mastodon received alice post"
      )

    _ = delete_status!(ctx.pleroma1_base_url, ctx.alice_access_token, alice_status_id)

    wait_until!(
      fn ->
        status_gone?(
          ctx.mastodon_base_url,
          ctx.carol_access_token,
          mastodon_view_of_alice_status["id"]
        )
      end,
      "mastodon removed deleted alice post"
    )

    carol_text = "fedbox: delete me (from mastodon) #{unique}"
    carol_status = create_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_text)
    carol_status_id = carol_status["id"]

    carol_uri_variants =
      carol_status
      |> status_uri()
      |> actor_id_variants()

    alice_view_of_carol_status =
      wait_until!(
        fn ->
          find_status_by_uri_variant(
            ctx.pleroma1_base_url,
            ctx.alice_access_token,
            carol_uri_variants
          )
        end,
        "pleroma1 received carol post"
      )

    _ = delete_status!(ctx.mastodon_base_url, ctx.carol_access_token, carol_status_id)

    wait_until!(
      fn ->
        status_gone?(
          ctx.pleroma1_base_url,
          ctx.alice_access_token,
          alice_view_of_carol_status["id"]
        )
      end,
      "pleroma1 removed deleted carol post"
    )
  end

end
