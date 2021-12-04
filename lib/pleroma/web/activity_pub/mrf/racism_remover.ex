defmodule Pleroma.Web.ActivityPub.MRF.RacismRemover do
  require Logger
  @behaviour Pleroma.Web.ActivityPub.MRF

  @impl true
  def filter(%{"type" => "Delete", "actor" => actor} = object) do
    actor_info = URI.parse(actor)

    if(actor_info.host == "bae.st") do
      Logger.warn("DELETE from NB, not rejecting:  #{inspect(object)}")
      {:ok, object}
    else
      Logger.warn("DELETE rejected: #{inspect(object)}")
      {:reject, object}
    end
  end

  @impl true
  def filter(object), do: {:ok, object}

  @impl true
  def describe, do: {:ok, %{}}
end
