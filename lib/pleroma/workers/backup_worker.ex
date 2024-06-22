# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.BackupWorker do
  use Oban.Worker, queue: :slow, max_attempts: 1

  alias Oban.Job
  alias Pleroma.User.Backup

  @impl Oban.Worker
  def perform(%Job{
        args: %{"op" => "process", "backup_id" => backup_id}
      }) do
    with {:ok, %Backup{} = backup} <- Backup.get(backup_id),
         {:ok, updated_backup} <- Backup.run(backup.user),
         {:ok, uploaded_backup} <- Backup.upload(updated_backup),
         {:ok, _job} <- Backup.schedule_delete(uploaded_backup),
         :ok <- Backup.remove_outdated(uploaded_backup.user),
         :ok <- maybe_deliver_email(uploaded_backup) do
      {:ok, uploaded_backup}
    end
  end

  def perform(%Job{args: %{"op" => "delete", "backup_id" => backup_id}}) do
    case Backup.get(backup_id) do
      %Backup{} = backup -> Backup.delete_archive(backup)
      nil -> :ok
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :infinity

  defp has_email?(user) do
    not is_nil(user.email) and user.email != ""
  end

  defp maybe_deliver_email(backup) do
    has_mailer = Pleroma.Config.get([Pleroma.Emails.Mailer, :enabled])
    backup = backup |> Pleroma.Repo.preload(:user)

    if has_email?(backup.user) and has_mailer do
      backup
      |> Pleroma.Emails.UserEmail.backup_is_ready_email()
      |> Pleroma.Emails.Mailer.deliver()

      :ok
    else
      :ok
    end
  end
end
