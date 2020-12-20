# Useful commands

This is a set of commands that may be useful for development. This is mostly meant for people who are new to development to help them get started.

## Pleroma/Elixir specific commands

```sh
# Run Pleroma
mix phx.server

# Run Pleroma in a iex shell
iex -S mix phx.server

# Format all relevant files
mix format mix.exs "test/**/*.{ex,exs}" "lib/**/*.{ex,exs}" "config/**/*.{ex,exs}" "priv/**/*.{ex,exs}"

# Run all test
mix test

# Only run the tests that failed the last time
mix test --failed

# Only test the files that have been impacted by the changes since the last run
mix test --stale

# Only test this specific file
mix test test/config/deprecation_warnings_test.exs

# Only run the tests that these lines are part of
mix test test/config/deprecation_warnings_test.exs:10:86:136

# Example of a call like a client does. This example fetches the 20 most recent notifications of the logged in user.
# To get a working `$BEARER_TOKEN`, you can open pleroma fe in Firefox > log in > F12 > Network tab > Rightclick a relevant call > Copy > Copy as curl > Past this in a text editor > This is the call that was made, you can take the `-H 'Authorization: Bearer $BEARER_TOKEN'` from there.
curl 'http://localhost:4000/api/v1/notifications?with_muted=true&limit=20' -H 'Authorization: Bearer $BEARER_TOKEN'
```

## Files

```sh 
# Find by filename (`./` is optional and is the path from where to start the search. The parameter after `-name` is the file- or foldername. the `*` is a wildcard.)
find ./ -name simple_policy.ex*

# Find by content (`l` is for only filename, no content. `R` is recursive, `i` is case insencitive)
grep -lRi '$WORD_TO_LOOK_FOR' ./
```
