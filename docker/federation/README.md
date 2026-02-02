# Federation-in-a-box (Pleroma)

This is a repo-local Docker Compose setup that runs **two Pleroma instances + Mastodon** in a private
container network and executes a small **federation smoke test suite**.

This environment is intentionally **not production-like**:

- It runs behind an internal Caddy reverse proxy (`gateway`) with **HTTP and internal TLS (HTTPS)**.
- It uses a private internal CA (from Caddy) and configures clients to trust it so federation can
  happen over HTTPS inside the Docker network.

## Usage

From the Pleroma repo root:

```bash
docker compose -f docker/federation/compose.yml up -d --build
docker compose -f docker/federation/compose.yml --profile fedtest run --rm fedtest
```

Or via Mix:

```bash
mix pleroma.fedbox
```

Cleanup:

```bash
docker compose -f docker/federation/compose.yml down -v
```

## Notes

- The test runner lives in `docker/federation/test_runner/` and is an **ExUnit** project using **Req**.
- Mastodon uses `${MASTODON_IMAGE}` (defaults to `ghcr.io/mastodon/mastodon:v4.5.3`).
- Pleroma is built from this repo via `../..` (the repo root).
- Default domains are `pleroma1.test`, `pleroma2.test`, `mastodon.test`.
- Seeded users are `alice@pleroma1.test`, `bob@pleroma2.test`, `carol@mastodon.test` with password `password`.
- The smoke tests cover follow, post delivery, favourites, boosts, and deletes across Pleroma↔Pleroma and Pleroma↔Mastodon.
