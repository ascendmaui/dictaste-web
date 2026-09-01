# GitHub Status

Last updated: 2026-09-01

## Connected account

- GitHub app account: `ascendmaui`
- Recovery repository: `https://github.com/ascendmaui/dictaste-web`
- Recovery pull request: `https://github.com/ascendmaui/dictaste-web/pull/1`

## What is online

The connected GitHub app created an import branch and pull request with a recovery handoff file. That file records the recovered local repo path, bundle checksums, and verified Google Drive backup paths.

## Remaining local Git step

The Mac command-line Git credential still uses the suspended `johnmatveyev-lab` account, so direct `git push` is blocked until `gh` is reauthenticated as `ascendmaui`.

After local GitHub login is fixed, run:

```bash
cd /Users/john/Documents/Codex/2026-08-31/referenced-chatgpt-conversation-this-is-an/outputs/Dictaste-Recovered
git remote set-url origin https://github.com/ascendmaui/dictaste-web.git
git push -u origin main:dictaste-recovered-2026-09-01
```

Then merge or replace PR 1 with the full recovered source branch.

