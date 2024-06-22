# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.User.Backup do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import Pleroma.Web.Gettext

  require Logger
  require Pleroma.Constants

  alias Pleroma.Activity
  alias Pleroma.Bookmark
  alias Pleroma.Config
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.ActivityPub.UserView
  alias Pleroma.Workers.BackupWorker

  @type t :: %__MODULE__{}

  schema "backups" do
    field(:content_type, :string)
    field(:file_name, :string)
    field(:file_size, :integer, default: 0)
    field(:processed, :boolean, default: false)
    field(:tempfile, :string)

    belongs_to(:user, User, type: FlakeId.Ecto.CompatType)

    timestamps()
  end

  @doc """
  Schedules a job to backup a user if the number of backup requests has not exceeded the limit.

  Admins can directly call new/1 and schedule_backup/1 to bypass the limit.
  """
  @spec user(User.t()) :: {:ok, Oban.Job.t()} | {:error, any()}
  def user(user) do
    days = Config.get([__MODULE__, :limit_days])

    with true <- permitted?(user),
         %__MODULE__{} = backup <- new(user) do
      schedule_backup(backup)
    else
      false ->
        {:error,
         dngettext(
           "errors",
           "Last export was less than a day ago",
           "Last export was less than %{days} days ago",
           days,
           days: days
         )}

      e ->
        {:error, e}
    end
  end

  @doc "Generates a %Backup{} for a user with a random file name"
  @spec new(User.t()) :: t()
  def new(user) do
    rand_str = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    datetime = Calendar.NaiveDateTime.Format.iso8601_basic(NaiveDateTime.utc_now())
    name = "archive-#{user.nickname}-#{datetime}-#{rand_str}.zip"

    %__MODULE__{
      content_type: "application/zip",
      file_name: name
    }
  end

  @doc "Schedules the execution of the provided backup"
  @spec schedule_backup(t()) :: {:ok, Oban.Job.t()} | {:error, any()}
  def schedule_backup(backup) do
    with {:ok, _} <- Repo.insert(backup) do
      %{"op" => "process", "backup_id" => backup.id}
      |> BackupWorker.new()
      |> Oban.insert()
    end
  end

  @doc "Deletes the backup archive file and removes the database record"
  @spec delete_archive(t()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete_archive(backup) do
    uploader = Config.get([Pleroma.Upload, :uploader])

    with :ok <- uploader.delete_file(Path.join("backups", backup.file_name)) do
      Repo.delete(backup)
    end
  end

  @doc "Schedules a job to delete the backup archive"
  @spec schedule_delete(t()) :: {:ok, Oban.Job.t()} | {:error, any()}
  def schedule_delete(backup) do
    days = Config.get([Backup, :purge_after_days])
    time = 60 * 60 * 24 * days
    scheduled_at = Calendar.NaiveDateTime.add!(backup.inserted_at, time)

    %{"op" => "delete", "backup_id" => backup.id}
    |> BackupWorker.new(scheduled_at: scheduled_at)
    |> Oban.insert()
  end

  defp permitted?(user) do
    with {_, %__MODULE__{inserted_at: inserted_at}} <- {:last, get_last(user)},
         days = Config.get([__MODULE__, :limit_days]),
         diff = Timex.diff(NaiveDateTime.utc_now(), inserted_at, :days),
         {_, true} <- {:diff, diff > days} do
      true
    else
      {:last, nil} -> true
      {:diff, false} -> false
    end
  end

  @doc "Returns last backup for the provided user"
  @spec get_last(User.t()) :: t()
  def get_last(%User{id: user_id}) do
    __MODULE__
    |> where(user_id: ^user_id)
    |> order_by(desc: :id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Lists all existing backups for a user"
  @spec list(User.t()) :: [Ecto.Schema.t() | term()]
  def list(%User{id: user_id}) do
    __MODULE__
    |> where(user_id: ^user_id)
    |> order_by(desc: :id)
    |> Repo.all()
  end

  @doc "Schedules deletion of all but the the most recent backup"
  @spec remove_outdated(User.t()) :: :ok
  def remove_outdated(user) do
    with %__MODULE__{} = latest_backup <- get_last(user) do
      __MODULE__
      |> where(user_id: ^user.id)
      |> where([b], b.id != ^latest_backup.id)
      |> Repo.all()
      |> Enum.each(&schedule_delete/1)
    else
      _ -> :ok
    end
  end

  def get(id), do: Repo.get(__MODULE__, id)

  @doc "Generates changeset for %Pleroma.User.Backup{}"
  @spec changeset(%__MODULE__{}, map()) :: %Ecto.Changeset{}
  def changeset(backup \\ %__MODULE__{}, attrs) do
    backup
    |> cast(attrs, [:content_type, :file_name, :file_size, :processed, :tempfile])
  end

  @doc "Updates the backup record"
  @spec update_backup(%__MODULE__{}, map()) :: {:ok, %__MODULE__{}} | {:error, %Ecto.Changeset{}}
  def update_backup(%__MODULE__{} = backup, attrs) do
    backup
    |> changeset(attrs)
    |> Repo.update()
  end

  @files [
    ~c"actor.json",
    ~c"outbox.json",
    ~c"likes.json",
    ~c"bookmarks.json",
    ~c"followers.json",
    ~c"following.json"
  ]

  @spec run(t()) :: {:ok, t()} | {:error, :failed}
  def run(%__MODULE__{} = backup) do
    backup = Repo.preload(backup, :user)
    dir = backup_tempdir(backup)

    with :ok <- File.mkdir(dir),
         :ok <- actor(dir, backup.user),
         :ok <- statuses(dir, backup.user),
         :ok <- likes(dir, backup.user),
         :ok <- bookmarks(dir, backup.user),
         :ok <- followers(dir, backup.user),
         :ok <- following(dir, backup.user),
         {:ok, zip_path} <- :zip.create(backup.file_name, @files, cwd: dir),
         {:ok, _} <- File.rm_rf(dir),
         {:ok, updated_backup} <- update_backup(backup, %{tempfile: zip_path}) do
      {:ok, updated_backup}
    else
      _ ->
        cleanup(backup)
        {:error, :failed}
    end
  end

  def dir(name) do
    dir = Config.get([__MODULE__, :dir]) || System.tmp_dir!()
    Path.join(dir, name)
  end

  def upload(%__MODULE__{tempfile: tempfile} = backup) when is_binary(tempfile) do
    uploader = Config.get([Pleroma.Upload, :uploader])

    upload = %Pleroma.Upload{
      name: backup.file_name,
      tempfile: tempfile,
      content_type: backup.content_type,
      path: Path.join("backups", backup.file_name)
    }

    with {:ok, _} <- Pleroma.Uploaders.Uploader.put_file(uploader, upload),
         :ok <- File.rm(tempfile) do
      {:ok, upload}
    end
  end

  defp actor(dir, user) do
    with {:ok, json} <-
           UserView.render("user.json", %{user: user})
           |> Map.merge(%{"likes" => "likes.json", "bookmarks" => "bookmarks.json"})
           |> Jason.encode() do
      File.write(Path.join(dir, "actor.json"), json)
    end
  end

  defp write_header(file, name) do
    IO.write(
      file,
      """
      {
        "@context": "https://www.w3.org/ns/activitystreams",
        "id": "#{name}.json",
        "type": "OrderedCollection",
        "orderedItems": [

      """
    )
  end

  defp backup_tempdir(backup) do
    name = String.trim_trailing(backup.file_name, ".zip")
    dir(name)
  end

  defp cleanup(backup) do
    dir = backup_tempdir(backup)
    File.rm_rf(dir)
  end

  defp write(query, dir, name, fun) do
    path = Path.join(dir, "#{name}.json")

    chunk_size = Config.get([__MODULE__, :process_chunk_size])

    with {:ok, file} <- File.open(path, [:write, :utf8]),
         :ok <- write_header(file, name) do
      total =
        query
        |> Pleroma.Repo.chunk_stream(chunk_size, _returns_as = :one, timeout: :infinity)
        |> Enum.reduce(0, fn i, acc ->
          with {:ok, data} <-
                 (try do
                    fun.(i)
                  rescue
                    e -> {:error, e}
                  end),
               {:ok, str} <- Jason.encode(data),
               :ok <- IO.write(file, str <> ",\n") do
            acc + 1
          else
            {:error, e} ->
              Logger.warning(
                "Error processing backup item: #{inspect(e)}\n The item is: #{inspect(i)}"
              )

              acc

            _ ->
              acc
          end
        end)

      with :ok <- :file.pwrite(file, {:eof, -2}, "\n],\n  \"totalItems\": #{total}}") do
        File.close(file)
      end
    end
  end

  defp bookmarks(dir, %{id: user_id} = _user) do
    Bookmark
    |> where(user_id: ^user_id)
    |> join(:inner, [b], activity in assoc(b, :activity))
    |> select([b, a], %{id: b.id, object: fragment("(?)->>'object'", a.data)})
    |> write(dir, "bookmarks", fn a -> {:ok, a.object} end)
  end

  defp likes(dir, user) do
    user.ap_id
    |> Activity.Queries.by_actor()
    |> Activity.Queries.by_type("Like")
    |> select([like], %{id: like.id, object: fragment("(?)->>'object'", like.data)})
    |> write(dir, "likes", fn a -> {:ok, a.object} end)
  end

  defp statuses(dir, user) do
    opts =
      %{}
      |> Map.put(:type, ["Create", "Announce"])
      |> Map.put(:actor_id, user.ap_id)

    [
      [Pleroma.Constants.as_public(), user.ap_id],
      User.following(user),
      Pleroma.List.memberships(user)
    ]
    |> Enum.concat()
    |> ActivityPub.fetch_activities_query(opts)
    |> write(
      dir,
      "outbox",
      fn a ->
        with {:ok, activity} <- Transmogrifier.prepare_outgoing(a.data) do
          {:ok, Map.delete(activity, "@context")}
        end
      end
    )
  end

  defp followers(dir, user) do
    User.get_followers_query(user)
    |> write(dir, "followers", fn a -> {:ok, a.ap_id} end)
  end

  defp following(dir, user) do
    User.get_friends_query(user)
    |> write(dir, "following", fn a -> {:ok, a.ap_id} end)
  end
end
