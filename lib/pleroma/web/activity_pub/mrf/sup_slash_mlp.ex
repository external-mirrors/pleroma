defmodule Pleroma.Web.ActivityPub.MRF.SupSlashMLP do
  require Logger
  @behaviour Pleroma.Web.ActivityPub.MRF

  @impl true
  def filter(
        %{
          "type" => "Create",
          "actor" => actor,
          "to" => mto,
          "cc" => mcc,
          "object" =>
            %{
              "type" => "Note",
              "summary" => "/mlp/",
              "to" => oto,
              "cc" => occ
            } = object
        } = message
      ) do
    # Whoever is running @bonzileaks@shitposter.club decided that
    # they'd "unmask" all the people having fun.  You took a
    # semi-anonymous fun thing and turned it into an administrative
    # headache.
    # The downside is that you will no longer see the posts that
    # are made by people you are following, in addition to the
    # downsides this creates for me, plus this is terrible code
    # because I do not care about Elixir.
    actor_info = URI.parse(actor)

    if(actor_info.host == "bae.st") do
      Logger.warn("sup /mlp/ #{inspect(message)}")
      # There's probably a better way to do this in Elixir, but...
      # "When in doubt, use brute force." -- Ken Thompson

      afol = "#{actor}/followers"

      object =
        object
        |> Map.put("actor", "https://bae.st/users/mlp")
        |> Map.put(
          "to",
          Enum.map(oto, fn
            i when i == afol -> "https://bae.st/users/mlp/followers"
            i -> i
          end)
        )
        |> Map.put(
          "cc",
          Enum.map(occ, fn
            i when i == afol -> "https://bae.st/users/mlp/followers"
            i -> i
          end)
        )

      message =
        message
        |> Map.put("actor", "https://bae.st/users/mlp")
        |> Map.put(
          "to",
          Enum.map(mto, fn
            i when i == afol -> "https://bae.st/users/mlp/followers"
            i -> i
          end)
        )
        |> Map.put(
          "cc",
          Enum.map(mcc, fn
            i when i == afol -> "https://bae.st/users/mlp/followers"
            i -> i
          end)
        )
        |> Map.put("object", object)

      Logger.warn("sup /mlp/ NEW MESSAGE:  #{inspect(message)}")
      {:ok, message}
    else
      {:ok, message}
    end
  end

  @impl true
  def filter(message), do: {:ok, message}
  @impl true
  def describe, do: {:ok, %{}}
end
