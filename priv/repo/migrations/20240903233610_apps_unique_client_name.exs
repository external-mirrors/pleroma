defmodule Pleroma.Repo.Migrations.AppsUniqueClientName do
  use Ecto.Migration

  alias Pleroma.Repo
  alias Pleroma.Web.OAuth.App

  def change do
    delete_duplicates()

    create_if_not_exists(unique_index(:apps, [:client_name]))
  end

  defp delete_duplicates() do
    Repo.all(App)
    |> Enum.group_by(fn x -> Map.get(x, :client_name) end)
    |> Enum.each(fn x ->
      case x do
        {_, [_head | tail]} ->
          for app <- tail do
            {:ok, _} = Repo.delete(app)
          end

        _ ->
          :ok
      end
    end)
  end
end
