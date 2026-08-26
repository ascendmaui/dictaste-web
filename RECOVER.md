# Dictaste web source recovery — 2026-08-26

**Status:** FAIL — source tree not recovered.

## Provenance

| Field | Value |
|---|---|
| Original git SHA | `1737a99b98c2d32251056013a63e9374964e49c9` |
| Production deployment | `dpl_9mfX4E4tch8ZR37y4BMwaYFRcy2R` |
| Vercel project | `dictaste` (`prj_tARxt9Q8BQkr5U9Oj0UXs6b3xhtM`) |
| Vercel team | `johnmatveyev-lab` (`team_CWFHuApyeVOOzrPcMa3XZmbO`) |
| Original GitHub | `johnmatveyev-lab/dictaste-web` (account 404) |
| Recovery target | https://github.com/ascendmaui/dictaste-web |
| File count recovered | 0 |

## What was tried

1. Vercel MCP `get_deployment` — production READY; meta confirms git source SHA `1737a99` and commit message `ship: admin control center with visitor intelligence and affiliate ops`. Framework Next.js 16.3.0 (Turbopack).
2. Vercel REST `GET /v6/deployments/:id/files` + `GET /v8/deployments/:id/files/:fileId` — **source file tree not_found** (git deployments do not retain a retrievable source tree). Confirmed gone. Did not scrape `/vercel/output` or live HTML.
3. Vercel CLI config at `/home/box/.local/share/com.vercel.cli/config.json` — telemetry only; no token. `VERCEL_TOKEN` unset. Did not invent a token or relink production.
4. GitHub MCP as `ascendmaui` — original repo 404; no forks; commit SHA not searchable. Dest repo exists with README recovery note only.
5. Local clone — none on the box. User machine (Grok Bot desktop) was **not connected**, so no ExternalShell search of John's disk.

## Not done (on purpose)

- No production relink / redeploy (would risk clobbering live dictaste.com).
- No Vercel/GitHub connect cards.
- No build-output scrape (`.next`, lambdas, live HTML).
- Soft-launch HOLD. No posts.

## Next (human)

Need a copy of `johnmatveyev-lab/dictaste-web` at SHA `1737a99` from a laptop, Time Machine, or another clone, then push to this repo.
