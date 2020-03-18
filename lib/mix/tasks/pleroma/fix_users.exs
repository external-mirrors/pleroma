alias Pleroma.{User, Repo}

import Ecto.Query
import Ecto.Changeset

from(
  u in User,
  where: fragment("? ->> 'id' IS NULL", u.info),
  update: [
    set: [info: nil]
  ]
)
|> Repo.update_all([])

User
|> where([user], fragment("? ->> 'id' IS NULL", user.info))
|> Repo.all()
|> Enum.each(fn user ->
  change(user)
  |> put_embed(:info, %User.Info{locked: true, hide_followers: true, hide_follows: true})
  |> User.update_and_set_cache()
end)
