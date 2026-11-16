# ezcamps shared ratings

Cloudflare Worker + D1 behind "From other campers" in the app.
Live at `https://ezcamps-ratings.harikanth-ai.workers.dev`, database `ezcamps-ratings`.

## API

| Method | Path | Auth | What |
|---|---|---|---|
| GET | `/v1/sites/{siteId}/ratings` | optional | Score, counts, recent tags, newest 30 ratings (`mine` when signed in) |
| GET | `/v1/summaries?ids=a,b` | – | Scores for up to 200 sites |
| POST | `/v1/auth/apple` | – | `{identityToken}` from Sign in with Apple → `{token}` (180 days) |
| PUT | `/v1/ratings/{uuid}` | yes | Create or update; one per person, site and night |
| DELETE | `/v1/ratings/{uuid}` | yes | Delete your rating |
| POST | `/v1/ratings/{uuid}/report` | yes | `{reason}`; 3 reports hide a rating |
| DELETE | `/v1/account` | yes | Delete the account and everything it shared |

**Score:** weighted average. Verified (logged within 500 m, checked on the phone) counts double,
and weight halves for every year since the night camped.

**Privacy:** no names or emails. Users are an HMAC of Apple's user id (`SUB_PEPPER` secret), and
session tokens are stored only as SHA-256 hashes. Don't rotate `SUB_PEPPER`: it would detach
every account from its ratings. Don't rotate `TOKEN_KEY` either: stored Apple refresh tokens become
unreadable and account deletion can no longer revoke Sign in with Apple.

**Sign in with Apple revocation:** at sign-in the app sends Apple's authorization code; the Worker
trades it for a refresh token (stored AES-GCM encrypted) and revokes it on `DELETE /v1/account`.
Secrets: `APPLE_KEY_P8` (the .p8, Key ID 742GSDKA8H), `APPLE_KEY_ID`, `TOKEN_KEY`; `APPLE_TEAM_ID` is a var.

**Limits:** 40 rating writes per person per day, 8 KB bodies, 1000-character notes, known tags only.

## Develop

```sh
npm install
printf 'SUB_PEPPER=local\nALLOW_DEV_AUTH=1\n' > .dev.vars   # dev sign-in route, local only
npx wrangler d1 migrations apply ezcamps-ratings --local
npm run dev            # then, in another shell:
npm test               # end-to-end tests against localhost:8787
npm run typecheck
```

Deploy: `npx wrangler d1 migrations apply ezcamps-ratings --remote && npm run deploy`.
