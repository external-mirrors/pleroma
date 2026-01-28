# Migrating from Akkoma

## Code migration

### From source

If you're running Akkoma from source, you need to set the origin repository URL to upstream and pull the changes.

```bash
git remote set-url origin https://git.pleroma.social/pleroma/pleroma
git pull -r
```

Then, install the dependencies and compile as usual:

```bash
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix compile
```

Remove installed frontends from the static directory. By default:

```bash
rm -r instance/static/frontends
```

## Database migration

> Note: You will lose data related about Akkoma-specific features, including: MastoFE settings, user frontend profiles, status auto-expiration config, hashtag follows, DM restrictions and auto follow-back. Consider taking a backup.

To rollback Akkoma-specific migrations:

- OTP: `./bin/pleroma_ctl rollback --migrations-path priv/repo/optional_migrations/akkoma_rollbacks --all`
- From source: `MIX_ENV=prod mix ecto.rollback --migrations-path priv/repo/optional_migrations/akkoma_rollbacks --all`

Then, just

- OTP: `./bin/pleroma_ctl migrate`
- From source: `MIX_ENV=prod mix ecto.migrate`

to apply Pleroma database migrations.