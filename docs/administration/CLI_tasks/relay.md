<!--
SPDX-FileCopyrightText: 2022 Pleroma Authors <https://pleroma.social/>

SPDX-License-Identifier: CC-BY-4.0
-->

# Managing relays

{! backend/administration/CLI_tasks/general_cli_task_info.include !}

## Follow a relay

=== "OTP"

    ```sh
    ./bin/pleroma_ctl relay follow <relay_url>
    ```

=== "From Source"

    ```sh
    mix pleroma.relay follow <relay_url>
    ```

## Unfollow a remote relay

=== "OTP"

    ```sh
    ./bin/pleroma_ctl relay unfollow <relay_url>
    ```

=== "From Source"

    ```sh
    mix pleroma.relay unfollow <relay_url>
    ```

## List relay subscriptions

=== "OTP"

    ```sh
    ./bin/pleroma_ctl relay list
    ```

=== "From Source"

    ```sh
    mix pleroma.relay list
    ```
