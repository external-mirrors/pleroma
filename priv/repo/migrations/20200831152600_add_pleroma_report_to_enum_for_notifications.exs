defmodule Pleroma.Repo.Migrations.ChangeTypeToEnumForNotifications do
  use Ecto.Migration

  def up do
    alter table(:notifications) do
      modify(:type, :string)
    end

    """
    drop type notification_type
    """
    |> execute()

    """
    create type notification_type as enum (
    'favourite',
    'follow',
    'follow_request',
    'mention',
    'move',
    'pleroma:chat_mention',
    'pleroma:emoji_reaction',
    'pleroma:report',
    'reblog'
    )
    """
    |> execute()

    """
    alter table notifications 
    alter column type type notification_type using (type::notification_type)
    """
    |> execute()
  end

  def down do
    alter table(:notifications) do
      modify(:type, :string)
    end
    
    """
    delete from notifications where type = 'pleroma:report'
    """
    |> execute()

    """
    drop type notification_type
    """
    |> execute()

    """
    create type notification_type as enum (
      'follow',
      'follow_request',
      'mention',
      'move',
      'pleroma:emoji_reaction',
      'pleroma:chat_mention',
      'reblog',
      'favourite'
    )
    """
    |> execute()

    """
    alter table notifications 
    alter column type type notification_type using (type::notification_type)
    """
    |> execute()
  end
end
