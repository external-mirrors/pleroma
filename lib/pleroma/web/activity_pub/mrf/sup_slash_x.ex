defmodule Pleroma.Web.ActivityPub.MRF.SupSlashX do
  require Logger
  @behaviour Pleroma.Web.ActivityPub.MRF

  @impl true
  def filter(
        %{
          "type" => "Create",
          "actor" => actor,
          "object" =>
            %{
              "type" => "Note",
              "summary" => "/x/"
            } = object
        } = message
      ) do
    actor_info = URI.parse(actor)

    if(actor_info.host == "neckbeard.xyz") do
      # Logger.warn("sup /x/ #{inspect(object)}")

      object =
        object
        |> Map.put("actor", "https://neckbeard.xyz/users/x")

      message =
        message
        |> Map.put("actor", "https://neckbeard.xyz/users/x")
        |> Map.put("object", object)

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
