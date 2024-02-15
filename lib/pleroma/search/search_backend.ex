defmodule Pleroma.Search.SearchBackend do
  @doc """
  Search statuses with a query, restricting to only those the user should have access to.
  """
  @callback search(user :: Pleroma.User.t(), query :: String.t(), options :: [any()]) :: [
              Pleroma.Activity.t()
            ]

  @doc """
  Add the object associated with the activity to the search index.
  When the activity is passed we schedule the job; when the activity id is passed we execute the work.
  """
  @callback add_to_index(activity :: Pleroma.Activity.t()) :: {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset() | term()}
  @callback add_to_index(activity_id :: String.t()) :: :ok | {:error, any()}

  @doc """
  Remove the object from the index.

  Just the object, as opposed to the whole activity, is passed, since the object
  is what contains the actual content and there is no need for filtering when removing
  from index.

  When the object is passed we schedule the job; when the object id is passed we execute the work.
  """
  @callback remove_from_index(object :: Pleroma.Object.t()) :: {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset() | term()}
  @callback remove_from_index(object_id :: String.t()) :: :ok | {:error, any()}
end
