# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.RemoteRepliesFetcherWorkerTest do
  use Pleroma.DataCase, async: false
  use Oban.Testing, repo: Pleroma.Repo

  import Pleroma.Factory
  import Tesla.Mock

  alias Pleroma.Workers.RemoteFetcherWorker
  alias Pleroma.Workers.RemoteRepliesFetcherWorker

  @actor "https://remote.example/users/alice"
  @root_id "https://remote.example/objects/root"
  @root_collection_id "https://remote.example/objects/root/replies"
  @parent_id "https://remote.example/objects/parent"
  @activity_id "https://remote.example/activities/parent"
  @collection_id "https://remote.example/objects/parent/replies"
  @page_2 "https://remote.example/objects/parent/replies?page=2"
  @page_3 "https://remote.example/objects/parent/replies?page=3"
  @other_collection_id "https://other.example/objects/parent/replies"
  @other_scheme_collection_id "http://remote.example/objects/parent/replies"
  @other_port_collection_id "https://remote.example:8443/objects/parent/replies"
  @reply_1 "https://remote.example/objects/reply-1"
  @reply_2 "https://remote.example/objects/reply-2"
  @reply_3 "https://remote.example/objects/reply-3"

  setup do
    clear_config([:activitypub, :remote_replies_collection_refresh],
      enabled: true,
      schedule: [0],
      triggered_refresh_delay: 0,
      triggered_refresh_ancestor_depth: 3,
      max_pages: 2,
      max_items: 40
    )

    user = insert(:user, local: false, ap_id: @actor)

    parent =
      insert(:note,
        user: user,
        object_local: false,
        data: %{
          "id" => @parent_id,
          "actor" => @actor,
          "attributedTo" => @actor,
          "replies_collection" => @collection_id
        }
      )

    insert(:note_activity,
      user: user,
      note: parent,
      local: false,
      data_attrs: %{"id" => @activity_id}
    )

    %{parent: parent, user: user}
  end

  test "enqueues a debounced refresh for a reply's parent", %{parent: parent, user: user} do
    reply =
      insert(:note,
        user: user,
        object_local: false,
        data: %{
          "id" => @reply_1,
          "actor" => @actor,
          "attributedTo" => @actor,
          "inReplyTo" => parent.data["id"]
        }
      )

    assert :ok = RemoteRepliesFetcherWorker.enqueue_for_reply_ancestors(reply, 1)

    assert_enqueued(
      worker: RemoteRepliesFetcherWorker,
      args: %{
        "op" => "refresh_replies",
        "object_id" => @parent_id,
        "collection_id" => @collection_id,
        "depth" => 1,
        "refresh_index" => "triggered"
      }
    )
  end

  test "reschedules an already scheduled debounced refresh", %{parent: parent, user: user} do
    clear_config([:activitypub, :remote_replies_collection_refresh],
      enabled: true,
      schedule: [0],
      triggered_refresh_delay: 300,
      triggered_refresh_ancestor_depth: 3,
      max_pages: 2,
      max_items: 40
    )

    reply =
      insert(:note,
        user: user,
        object_local: false,
        data: %{
          "id" => @reply_1,
          "actor" => @actor,
          "attributedTo" => @actor,
          "inReplyTo" => parent.data["id"]
        }
      )

    assert :ok = RemoteRepliesFetcherWorker.enqueue_for_reply_ancestors(reply, 3)

    [%Oban.Job{args: args, scheduled_at: scheduled_at}] =
      all_enqueued(worker: RemoteRepliesFetcherWorker)

    assert args["depth"] == 3

    Process.sleep(10)

    new_collection_id = @collection_id <> "?generation=2"

    {:ok, _parent} =
      Pleroma.Object.update_data(parent, %{"replies_collection" => new_collection_id})

    assert :ok = RemoteRepliesFetcherWorker.enqueue_for_reply_ancestors(reply, 1)

    [%Oban.Job{args: args, scheduled_at: rescheduled_at}] =
      all_enqueued(worker: RemoteRepliesFetcherWorker)

    assert DateTime.compare(rescheduled_at, scheduled_at) == :gt
    assert args["collection_id"] == new_collection_id
    assert args["depth"] == 1
  end

  test "walks known ancestors within the configured trigger depth", %{parent: parent, user: user} do
    root =
      insert(:note,
        user: user,
        object_local: false,
        data: %{
          "id" => @root_id,
          "actor" => @actor,
          "attributedTo" => @actor,
          "replies_collection" => @root_collection_id
        }
      )

    {:ok, parent} = Pleroma.Object.update_data(parent, %{"inReplyTo" => root.data["id"]})

    reply =
      insert(:note,
        user: user,
        object_local: false,
        data: %{
          "id" => @reply_1,
          "actor" => @actor,
          "attributedTo" => @actor,
          "inReplyTo" => parent.data["id"]
        }
      )

    assert :ok = RemoteRepliesFetcherWorker.enqueue_for_reply_ancestors(reply, 3)

    assert_enqueued(
      worker: RemoteRepliesFetcherWorker,
      args: %{"object_id" => @parent_id, "depth" => 3, "refresh_index" => "triggered"}
    )

    assert_enqueued(
      worker: RemoteRepliesFetcherWorker,
      args: %{"object_id" => @root_id, "depth" => 2, "refresh_index" => "triggered"}
    )
  end

  test "does not walk known ancestors beyond the configured trigger depth", %{
    parent: parent,
    user: user
  } do
    clear_config([:activitypub, :remote_replies_collection_refresh],
      enabled: true,
      schedule: [0],
      triggered_refresh_delay: 0,
      triggered_refresh_ancestor_depth: 1,
      max_pages: 2,
      max_items: 40
    )

    root =
      insert(:note,
        user: user,
        object_local: false,
        data: %{
          "id" => @root_id,
          "actor" => @actor,
          "attributedTo" => @actor,
          "replies_collection" => @root_collection_id
        }
      )

    {:ok, parent} = Pleroma.Object.update_data(parent, %{"inReplyTo" => root.data["id"]})

    reply =
      insert(:note,
        user: user,
        object_local: false,
        data: %{
          "id" => @reply_1,
          "actor" => @actor,
          "attributedTo" => @actor,
          "inReplyTo" => parent.data["id"]
        }
      )

    assert :ok = RemoteRepliesFetcherWorker.enqueue_for_reply_ancestors(reply, 3)

    assert_enqueued(worker: RemoteRepliesFetcherWorker, args: %{"object_id" => @parent_id})
    refute_enqueued(worker: RemoteRepliesFetcherWorker, args: %{"object_id" => @root_id})
  end

  test "does not loop while walking known ancestors", %{parent: parent, user: user} do
    root =
      insert(:note,
        user: user,
        object_local: false,
        data: %{
          "id" => @root_id,
          "actor" => @actor,
          "attributedTo" => @actor,
          "replies_collection" => @root_collection_id
        }
      )

    {:ok, parent} = Pleroma.Object.update_data(parent, %{"inReplyTo" => root.data["id"]})
    {:ok, _root} = Pleroma.Object.update_data(root, %{"inReplyTo" => parent.data["id"]})

    reply =
      insert(:note,
        user: user,
        object_local: false,
        data: %{
          "id" => @reply_1,
          "actor" => @actor,
          "attributedTo" => @actor,
          "inReplyTo" => parent.data["id"]
        }
      )

    assert :ok = RemoteRepliesFetcherWorker.enqueue_for_reply_ancestors(reply, 3)

    jobs = all_enqueued(worker: RemoteRepliesFetcherWorker)

    assert Enum.count(jobs, &(&1.args["refresh_index"] == "triggered")) == 2
    assert_enqueued(worker: RemoteRepliesFetcherWorker, args: %{"object_id" => @parent_id})
    assert_enqueued(worker: RemoteRepliesFetcherWorker, args: %{"object_id" => @root_id})
  end

  test "fetches an advertised collection and enqueues reply object fetches" do
    mock(fn
      %{method: :get, url: @collection_id} ->
        activitypub_json(%{
          "id" => @collection_id,
          "type" => "OrderedCollection",
          "first" => %{
            "id" => @collection_id <> "?page=true",
            "type" => "OrderedCollectionPage",
            "partOf" => @collection_id,
            "orderedItems" => [@reply_1, %{"id" => @reply_2}]
          }
        })
    end)

    assert :ok =
             perform_job(RemoteRepliesFetcherWorker, %{
               "op" => "refresh_replies",
               "object_id" => @parent_id,
               "collection_id" => @collection_id,
               "depth" => 1,
               "refresh_index" => 0
             })

    assert_enqueued(
      worker: RemoteFetcherWorker,
      args: %{"op" => "fetch_remote", "id" => @reply_1, "depth" => 1}
    )

    assert_enqueued(
      worker: RemoteFetcherWorker,
      args: %{"op" => "fetch_remote", "id" => @reply_2, "depth" => 1}
    )
  end

  test "follows collection pagination within page and item limits" do
    clear_config([:activitypub, :remote_replies_collection_refresh],
      enabled: true,
      schedule: [0],
      max_pages: 2,
      max_items: 2
    )

    mock(fn
      %{method: :get, url: @collection_id} ->
        activitypub_json(%{
          "id" => @collection_id,
          "type" => "OrderedCollection",
          "first" => %{
            "id" => @collection_id <> "?page=true",
            "type" => "OrderedCollectionPage",
            "partOf" => @collection_id,
            "orderedItems" => [@reply_1],
            "next" => @page_2
          }
        })

      %{method: :get, url: @page_2} ->
        activitypub_json(%{
          "id" => @page_2,
          "type" => "OrderedCollectionPage",
          "partOf" => @collection_id,
          "orderedItems" => [@reply_2, @reply_3]
        })
    end)

    assert :ok =
             perform_job(RemoteRepliesFetcherWorker, %{
               "op" => "refresh_replies",
               "object_id" => @parent_id,
               "collection_id" => @collection_id,
               "depth" => 1,
               "refresh_index" => 0
             })

    assert_enqueued(worker: RemoteFetcherWorker, args: %{"id" => @reply_1})
    assert_enqueued(worker: RemoteFetcherWorker, args: %{"id" => @reply_2})
    refute_enqueued(worker: RemoteFetcherWorker, args: %{"id" => @reply_3})
  end

  test "fetches a linked first page" do
    mock(fn
      %{method: :get, url: @collection_id} ->
        activitypub_json(%{
          "id" => @collection_id,
          "type" => "OrderedCollection",
          "first" => %{
            "id" => @page_2,
            "type" => "OrderedCollectionPage",
            "partOf" => @collection_id
          }
        })

      %{method: :get, url: @page_2} ->
        activitypub_json(%{
          "id" => @page_2,
          "type" => "OrderedCollectionPage",
          "partOf" => @collection_id,
          "orderedItems" => [@reply_1]
        })
    end)

    assert :ok =
             perform_job(RemoteRepliesFetcherWorker, %{
               "op" => "refresh_replies",
               "object_id" => @parent_id,
               "collection_id" => @collection_id,
               "depth" => 1,
               "refresh_index" => 0
             })

    assert_enqueued(worker: RemoteFetcherWorker, args: %{"id" => @reply_1})
  end

  test "fetches a linked first page before its next page" do
    mock(fn
      %{method: :get, url: @collection_id} ->
        activitypub_json(%{
          "id" => @collection_id,
          "type" => "OrderedCollection",
          "first" => %{
            "id" => @page_2,
            "type" => "OrderedCollectionPage",
            "partOf" => @collection_id,
            "next" => @page_3
          }
        })

      %{method: :get, url: @page_2} ->
        activitypub_json(%{
          "id" => @page_2,
          "type" => "OrderedCollectionPage",
          "partOf" => @collection_id,
          "orderedItems" => [@reply_1]
        })

      %{method: :get, url: @page_3} ->
        activitypub_json(%{
          "id" => @page_3,
          "type" => "OrderedCollectionPage",
          "partOf" => @collection_id,
          "orderedItems" => [@reply_2]
        })
    end)

    assert :ok =
             perform_job(RemoteRepliesFetcherWorker, %{
               "op" => "refresh_replies",
               "object_id" => @parent_id,
               "collection_id" => @collection_id,
               "depth" => 1,
               "refresh_index" => 0
             })

    assert_enqueued(worker: RemoteFetcherWorker, args: %{"id" => @reply_1})
    refute_enqueued(worker: RemoteFetcherWorker, args: %{"id" => @reply_2})
  end

  test "does not refetch collection pages already seen" do
    test_pid = self()

    mock(fn
      %{method: :get, url: @collection_id} ->
        send(test_pid, :collection_fetched)

        activitypub_json(%{
          "id" => @collection_id,
          "type" => "OrderedCollection",
          "orderedItems" => [@reply_1],
          "next" => @collection_id
        })
    end)

    assert :ok =
             perform_job(RemoteRepliesFetcherWorker, %{
               "op" => "refresh_replies",
               "object_id" => @parent_id,
               "collection_id" => @collection_id,
               "depth" => 1,
               "refresh_index" => 0
             })

    assert_received :collection_fetched
    refute_received :collection_fetched
    assert_enqueued(worker: RemoteFetcherWorker, args: %{"id" => @reply_1})
  end

  test "ignores malformed collection item lists" do
    mock(fn
      %{method: :get, url: @collection_id} ->
        activitypub_json(%{
          "id" => @collection_id,
          "type" => "OrderedCollection",
          "orderedItems" => "not a list"
        })
    end)

    assert :ok =
             perform_job(RemoteRepliesFetcherWorker, %{
               "op" => "refresh_replies",
               "object_id" => @parent_id,
               "collection_id" => @collection_id,
               "depth" => 1,
               "refresh_index" => 0
             })

    assert all_enqueued(worker: RemoteFetcherWorker) == []
  end

  test "does not fetch a collection from another origin", %{parent: parent} do
    for collection_id <- [
          @other_collection_id,
          @other_scheme_collection_id,
          @other_port_collection_id
        ] do
      {:ok, parent} =
        parent
        |> Pleroma.Object.change(%{
          data: Map.put(parent.data, "replies_collection", collection_id)
        })
        |> Pleroma.Object.update_and_set_cache()

      assert {:cancel, :collection_origin} =
               perform_job(RemoteRepliesFetcherWorker, %{
                 "op" => "refresh_replies",
                 "object_id" => parent.data["id"],
                 "collection_id" => collection_id,
                 "depth" => 1,
                 "refresh_index" => 0
               })
    end
  end

  test "cancels permanent collection fetch errors" do
    mock(fn
      %{method: :get, url: @collection_id} ->
        %Tesla.Env{status: 404}
    end)

    assert {:cancel, :not_found} =
             perform_job(RemoteRepliesFetcherWorker, %{
               "op" => "refresh_replies",
               "object_id" => @parent_id,
               "collection_id" => @collection_id,
               "depth" => 1,
               "refresh_index" => 0
             })
  end

  test "retries transient collection fetch errors" do
    mock(fn
      %{method: :get, url: @collection_id} ->
        {:error, :timeout}
    end)

    assert {:error, :timeout} =
             perform_job(RemoteRepliesFetcherWorker, %{
               "op" => "refresh_replies",
               "object_id" => @parent_id,
               "collection_id" => @collection_id,
               "depth" => 1,
               "refresh_index" => 0
             })
  end

  test "does not fetch replies when the parent is not public", %{parent: parent} do
    {:ok, parent} = Pleroma.Object.update_data(parent, %{"to" => [@actor <> "/followers"]})

    assert {:cancel, :not_public} =
             perform_job(RemoteRepliesFetcherWorker, %{
               "op" => "refresh_replies",
               "object_id" => parent.data["id"],
               "collection_id" => @collection_id,
               "depth" => 1,
               "refresh_index" => 0
             })
  end

  defp activitypub_json(data) do
    %Tesla.Env{
      status: 200,
      headers: HttpRequestMock.activitypub_object_headers(),
      body: Jason.encode!(data)
    }
  end
end
