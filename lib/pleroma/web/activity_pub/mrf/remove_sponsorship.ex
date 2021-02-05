defmodule Site.RemoveSponsorship do
  @behaviour Pleroma.Web.ActivityPub.MRF

  @impl true
  def filter(
        %{
          "type" => "Create",
          "object" => %{"content" => content, "attachment" => _} = _child_object
        } = object
      ) do
    nc =
      content
      |> String.replace(~r/(<p>=&gt;|ufgloves).*/, "")
      |> String.replace(~r/<p>--<br \/>Original: <a href="https:\/\/www\.twitter\.com\/.*/, "")

    {:ok, put_in(object, ["object", "content"], nc)}
  end

  @impl true
  def filter(object), do: {:ok, object}

  @impl true
  def describe, do: {:ok, %{}}
end
