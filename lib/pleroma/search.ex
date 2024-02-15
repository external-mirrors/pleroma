defmodule Pleroma.Search do
  alias Pleroma.Config

  defdelegate add_to_index(activity), to: Config.get([Pleroma.Search, :module])
  defdelegate remove_from_index(object), to: Config.get([Pleroma.Search, :module])
  defdelegate search(query, options), to: Config.get([Pleroma.Search, :module])
end
