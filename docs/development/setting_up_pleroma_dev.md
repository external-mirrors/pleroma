# Setting up a Pleroma development environment

Pleroma requires some adjustments from the defaults for running the instance locally. The following should help you to get started.

## Forking

To upstream code, you make an account on git.pleroma.social if you don't already have one and fork the project in the webinterface to your own namespace.

## Installing

1. Install Pleroma as explained in the docs: https://docs-develop.pleroma.social/backend/installation/debian_based_en/ but with some exceptions:
    * Use your own repository instead of pleroma's and add pleroma as a remote `git remote add pleroma 'https://git.pleroma.social/pleroma/pleroma'`
    * You can skip systemd and nginx and all that stuff
    * No need to create a dedicated pleroma user, it's easier to just use your own user (although you can if you want)
    * For the DB you can still choose a dedicated user, the mix tasks set it up for you so it's no extra work for you
    * For domain you can use `localhost`
    * instead of creating a `prod.secret.exs`, create `dev.secret.exs`
    * No need to prefix with `MIX_ENV=prod`. We're using dev and that's the default MIX_ENV.
2. Change the dev.secret.exs
    * Change the scheme in `config :pleroma, Pleroma.Web.Endpoint` to http
    * If you want to change other settings, you can do that too.
3. You can now start the server `mix phx.server`. Once it's build and started, you can access the instance on `http://<host>:<port>` (e.g.http://localhost:4000 ) and should be able to do everything locally you normaly can.

Example config to change the scheme to http. Change the port if you want to run on another port.
```elixir
  config :pleroma, Pleroma.Web.Endpoint,
   url: [host: "localhost", scheme: "http", port: 4000],
```

Example config to disable captcha. This makes it a bit easier to create test-users.
```elixir
config :pleroma, Pleroma.Captcha,
  enabled: false
```

Example config to change loglevel to info
```elixir
config :logger, :console,
  # :debug :info :warning :error
  level: :info
```

## Testing

1. Make a `test.secret.exs` file with the content as shown below
2. Create the dbuser and test-db
    1. `cp config/setup_db.psql config/setup_db_test.psql`
    2. `nano config/setup_db_test.psql`
    3. Change the databasename, user and password to the values for the test-database (e.g. 'pleroma_local_test' for database and user)
    4. `sudo -Hu postgres psql -f config/setup_db_test.psql`
    5. `sudo -Hu postgres psql -c "ALTER USER pleroma_local_test WITH CREATEDB;"`
3. Run the tests with `mix test` to see if they all pass. `mix test` will also create and migrate the database.

Content for the `test.secret.exs` file. Feel free to use another user, databasename or password, just make sure the database is dedicated for the testing environment.
```elixir
# Pleroma test configuration

# NOTE: This file should not be committed to a repo or otherwise made public
# without removing sensitive information.

import Config

config :pleroma, Pleroma.Repo,
  username: "pleroma_local_test",
  password: "mysuperduperpassword",
  database: "pleroma_local_test",
  hostname: "localhost"

```

## Updating

To update the develop branch

```sh
git checkout develop;
git pull pleroma develop;
mix deps.get;
mix ecto.migrate;
```

## Working on multiple branches

If you develop on a certain branch, it's possible you did migrations that aren't merged into another branch you're working on. If you have multiple things you're working on, it's probably best to set up multiple pleroma's with each their own database. If you finished with a branch and just want to switch back to develop to start a new branch from there, you can drop the database, switch back to develop and recreate the database

### Removign the database and user completely

```sh
sudo -Hu postgres psql -c "DROP DATABASE pleroma_local;"
sudo -Hu postgres psql -c "DROP USER pleroma_local;"
```

### Switch back to develop and update it to start a new branch from there

```sh
sudo -Hu postgres psql -c "DROP DATABASE pleroma_local;"
sudo -Hu postgres psql -c "DROP USER pleroma_local;"
git checkout develop
sudo -Hu postgres psql -f config/setup_db.psql
git pull pleroma develop;
mix deps.get;
mix ecto.migrate;
``` 
