# Chimpodoro party service

A Cloudflare Worker routes each invite code to one SQLite-backed Durable Object.
The object owns the timer, membership, host authority, deadline alarms and revision
checks. Hibernating WebSockets broadcast changes; clients draw countdowns locally.
The app bundles none of this development runtime.

## Live service

Deployed October 24, 2026 to the existing Cloudflare account on Workers Free:
`https://chimpodoro-party.chimpodoro-party.workers.dev`.
Health endpoint: `/health`. Chimpodoro 1.1.1 bundles this address.
Wrangler authenticates with the OS keychain; no credentials are in this repository.

## Deploy

Create a free Cloudflare account. Install Node.js 22+ and pnpm, then from this folder:

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm exec wrangler login
pnpm exec wrangler deploy
```

Sign in in the browser yourself. Do not put credentials in this repository.
Deployment creates `chimpodoro-party` and its Durable Object namespace in the
signed-in account. No paid plan is selected by these files. Free plan quotas still
apply; exceeding them can make parties unavailable. Review Cloudflare usage before
changing plans. The generated HTTPS `workers.dev` address needs no purchased domain.

For a different deployment, choose **Create / join party → Service…**, then paste its address.
Every participant must use the same address. You can instead bundle the final URL
in Info.plist's `PartyServiceURL` key for builds distributed to friends, so they
never have to configure a service. Do this only after the deployment is verified.

## Local checks

```sh
pnpm test
pnpm dev
# In another terminal (runs a real one-minute deadline):
node integration.mjs
```

Integration uses two WebSocket clients against the real local Workers runtime:
creation, join, common deadlines, pause, guest rejection, stale revisions, avatar
updates, private tokens, reconnect, deadline alarms, and host ending the party.
It does not establish that a cloud deployment or two physical Macs have been tested.

## Behavior

- Maximum eight members; ten-character random invite code (50 bits).
- Code possession permits joining. Each member then gets a separate random bearer
  token for their socket. Tokens are excluded from state broadcasts.
- Only the host controls start/pause/reset/skip/phase selection. Timer durations
  come from the host's settings at creation. Everyone follows one server deadline.
- Explicit host departure ends the party; a disconnected host can reconnect.
  Guests cannot take over. Parties expire 24 hours after creation, including stored
  profiles and credentials. Closing a socket does not remove membership.
- Delayed alarms advance once and start an optional next phase from server observation
  time; they never invent an unattended chain of sessions.
- Conflicting commands carry revisions and are rejected rather than applied twice.
- Request body and message limits are 4 KiB. HTTP requests are rate limited per IP;
  socket actions are limited per member. These controls reduce abuse, but are not
  a guarantee against exhaustion of the hosting account's quotas.
- No accounts, leaderboard, rankings, score storage, or task-text uploads. Future
  leaderboards would need a separate identity and scoring design; party snapshots
  must not be treated as trusted per-user achievement history.

## Data

The service holds chosen display names, cosmetic choices, member identifiers,
credentials, party settings, and current timer state until expiry or host end.
Cloudflare handles transport and may retain ordinary infrastructure/request logs
under the account's configuration. App history and task text never go to the
service. The macOS client keeps its membership credential in Keychain for relaunch
recovery; leaving clears it. Production clients require HTTPS and reject redirects.

## Live validation — October 24, 2026

Production deployment `b7a188e0-3302-418a-bbb2-2999b5f2e0bd` passed `/health`
and the full two-client integration test at the public HTTPS address, including
shared deadlines, host-only commands, stale revision rejection, profile updates,
credential privacy, reconnect, the actual one-minute alarm, and host ending.
A separate native macOS URLSession smoke test passed HTTPS party creation,
authenticated WebSocket state receipt, and explicit party cleanup. All synthetic
test parties were ended. The native app 1.1.1 bundles the service URL and is
installed locally; its 86 timer assertions pass. No paid plan was selected.
Two physical Macs on separate networks have not yet been tested.
