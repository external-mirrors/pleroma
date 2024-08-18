# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("pleroma.repo.query.total_time",
        reporter_options: [nav: "Repo"],
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("pleroma.repo.query.decode_time",
        reporter_options: [nav: "Repo"],
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("pleroma.repo.query.query_time",
        reporter_options: [nav: "Repo"],
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("pleroma.repo.query.queue_time",
        reporter_options: [nav: "Repo"],
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("pleroma.repo.query.idle_time",
        reporter_options: [nav: "Repo"],
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :megabyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Pleroma Metrics
      # ActivityPub
      sum("pleroma.activitypub.inbox.count",
        tags: [:type],
        reporter_options: [nav: "ActivityPub"],
        description: "Sum of activities received by type"
      ),
      sum("pleroma.activitypub.publisher.sum",
        tags: [:nickname],
        reporter_options: [nav: "ActivityPub"],
        description: "Sum of published activities by actor"
      ),
      sum("pleroma.activitypub.publisher.sum",
        tags: [:type],
        reporter_options: [nav: "ActivityPub"],
        description: "Sum of published activities by type"
      ),
      counter("pleroma.activitypub.publisher.count",
        tags: [:nickname],
        reporter_options: [nav: "ActivityPub"],
        description: "Counter of publishing events by activity actor"
      ),
      counter("pleroma.activitypub.publisher.count",
        tags: [:type],
        reporter_options: [nav: "ActivityPub"],
        description: "Counter of publishing events by activity type"
      ),

      # OAuth
      sum("pleroma.user.o_auth.success.count",
        tags: [:nickname],
        reporter_options: [nav: "OAuth"],
        description: "Sum of successful login attempts by user"
      ),
      # this graph is at risk of high cardinality as even incorrect
      # usernames are passed through as the nickname
      sum("pleroma.user.o_auth.failure.count",
        tags: [:nickname],
        reporter_options: [nav: "OAuth"],
        description: "Sum of failed login attempts by user"
      ),

      # Gun
      last_value("pleroma.connection_pool.worker.count",
        reporter_options: [nav: "Gun"],
        description: "Number of connection pool workers"
      ),
      counter("pleroma.connection_pool.client.add.count",
        reporter_options: [nav: "Gun"],
        description: "Counter of new connection events"
      ),
      counter("pleroma.connection_pool.client.dead.count",
        reporter_options: [nav: "Gun"],
        description: "Counter of dead connection events"
      ),
      counter("pleroma.connection_pool.provision_failure.count",
        reporter_options: [nav: "Gun"],
        description: "Counter of connection provisioning failure events"
      ),
      counter("pleroma.connection_pool.reclaim.stop.count",
        reporter_options: [nav: "Gun"],
        description: "Counter of idle connection reclaimation events"
      ),

      # Uploads
      last_value("pleroma.upload.success.size",
        reporter_options: [nav: "Uploads"],
        description: "Size of media uploads in bytes",
        unit: {:byte, :megabyte}
      ),
      counter("pleroma.upload.success.count",
        reporter_options: [nav: "Uploads"],
        description: "Count of media uploads by nickname",
        tags: [:nickname]
      ),
      summary("pleroma.upload.success.duration",
        reporter_options: [nav: "Uploads"],
        description: "Time spent receiving and processing uploads",
        unit: {:millisecond, :second}
      ),

      # Stats
      last_value("pleroma.stats.global.activities.count",
        reporter_options: [nav: "Stats"],
        description: "Total number of known activities per visibility type",
        tags: [:visibility]
      ),
      last_value("pleroma.stats.local.domains.count",
        reporter_options: [nav: "Stats"],
        description: "Total number of known domains"
      ),
      last_value("pleroma.stats.local.notes.count",
        reporter_options: [nav: "Stats"],
        description: "Total number of notes by local users"
      ),
      last_value("pleroma.stats.local.users.count",
        reporter_options: [nav: "Stats"],
        description: "Total number of local user accounts"
      )
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {Pleroma.Web, :count_users, []}
    ]
  end
end
