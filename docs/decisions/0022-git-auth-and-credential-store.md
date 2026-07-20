# ADR 0022: Git Authentication and Credential Storage

## Date
2026-07-20

## Status
Accepted

## Context
The `GitLibrary` backend previously shelled out to plain `git clone <url>` with no credential injection. Users had to configure HTTPS credentials or SSH agents externally. The LAN collaboration server bound `0.0.0.0` with no authentication, allowing any host on the LAN to push to the shared repository.

## Decision
1. **OS keyring for HTTPS tokens** (`credential_store.py`): Use the `keyring` library (service `varnamala.git`, account = URL host) for storing HTTPS tokens. When keyring is unavailable (headless Linux without D-Bus, sandboxed environments), transparently fall back to QSettings with base64 obfuscation and emit a one-time warning.

2. **SSH key path**: Stored in QSettings (not secret-grade). `GitLibrary._env_for()` injects `GIT_SSH_COMMAND=ssh -i <key> -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new`.

3. **HTTPS token injection**: `GitLibrary._run()` prepends `-c http.extraheader=Authorization: Bearer <token>` to git commands when a token is configured and the URL is not SSH.

4. **LAN server authentication** (`GitHTTPRequestHandler`): The Smart HTTP handler reads `auth_token`, `read_only`, and `allow_ips` from the `GitHTTPServer` instance. When `auth_token` is set, requests must include `Authorization: Bearer <token>`. When `read_only` is True, `git-receive-pack` (push) is rejected with 403. When `allow_ips` is non-empty, clients not in the list are rejected with 403.

5. **LAN server bind address**: Configurable via `lan_bind_address` (0.0.0.0 or 127.0.0.1). Port auto-increments on conflict (up to 10 attempts).

6. **Connected peers tracking**: The server maintains a `connected_peers` dict (IP -> last-seen timestamp) for presence display. Peers expire after 60s of inactivity.

## Consequences
- HTTPS token auth works without external credential helper configuration.
- SSH key override supports per-project keys.
- LAN collaboration is no longer open to the entire network by default.
- Read-only mode enables safe public sharing (clone/fetch only).
- The `keyring` dependency is added to `pyproject.toml`.
- Keyring unavailability degrades gracefully (fallback + warning, no crash).
