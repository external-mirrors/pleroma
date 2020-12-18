# Usefull commands

This is a set of commands that may be usefull for development. This is mostly meant for people who are new to development to help them get started.

## Pleroma/Elixir specific commands

```sh
# Run Pleroma
mix phx.server

# Run Pleroma in a iex shell
iex -S mix phx.server

# This formats all relevant files
mix format mix.exs "test/**/*.{ex,exs}" "lib/**/*.{ex,exs}" "config/**/*.{ex,exs}" "priv/**/*.{ex,exs}"

# Run all test
mix test

# Only test what has failed last time
mix test --failed

# Only test files that have been impacted by the changes since the last test
mix test --stale

# Only test this speccific file
mix test test/config/deprecation_warnings_test.exs

# Only test this speccific file and only the test that these line numbers are part of
mix test test/config/deprecation_warnings_test.exs:10:86:136

# Example of a call like a client does. This fetches the notifications. To get a working `$BEARER_TOKEN`, you can open pleroma fe in Firefox > log in with creds that may make the relevant call > F12 > Network tab > Rightclick whatever call > Copy > Copy as curl > Past this in a text editor > This is the call that was made, you can take the `-H 'Authorization: Bearer $BEARER_TOKEN'` from there.
curl 'http://localhost:4000/api/v1/notifications?with_muted=true&limit=1' -H 'Authorization: Bearer $BEARER_TOKEN'
```

## Files

```sh 
# Find by filename (`./` is optional and is the path from where to start the search. The parameter after `-name` is the file- or foldername. the `*` is a wildcard.)
find ./ -name simple_policy.ex*

# Find by content (`l` is for only filename, no content. `R` is recursive, `i` is case insencitive)
grep -lRi '$WORD_TO_LOOK_FOR' ./
```

## Git

```sh
# Stage files to commit
git add $file

# Commit files
git commit

# Push to remote repo
git push

# Pull latest changes from the upstream pleroma repo
git pull pleroma develop

# See files that have changed but not staged
git diff --name-only

# See files that have been staged
git diff --name-only --cached

# See diff in files that have changed but not staged
git diff

# See diff in files that have been staged
git diff --cached

# Example diff for unstaged diff of one specific file
git diff lib/pleroma/web/activity_pub/mrf/simple_policy.ex

# Revert changes in unstaged file
git checkout -- ./file/to/revert
```
