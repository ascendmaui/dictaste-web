# Dictaste Recovered Source Handoff

Created: 2026-09-01

This repository is connected under the new GitHub account `ascendmaui`. The full recovered source is ready locally and in two verified Google Drive backups.

## Local recovered repository

- Path: `/Users/john/Documents/Codex/2026-08-31/referenced-chatgpt-conversation-this-is-an/outputs/Dictaste-Recovered`
- Local Git branch: `main`
- Local Git HEAD: `81413b354ea16961c0974bcf7ea77a2336306705`
- Latest commit: `Add NVIDIA demo polish fallback`

## Verified backup bundle

- Local bundle: `/Users/john/Documents/Codex/2026-08-31/referenced-chatgpt-conversation-this-is-an/outputs/Dictaste-Backup-2026-09-01-nvidia-demo/source/Dictaste-Recovered.git.bundle`
- Bundle SHA-256: `542ddbf2681da1d94797d45f7a62e2837289185865dce644d20f46ec280af3ae`
- Source ZIP SHA-256: `31a7ad7ba10b39278fdf0a49bff1791030bf3db669ce6b4d71f23a0d41426249`

## Verified backup locations

- `/Users/john/Library/CloudStorage/GoogleDrive-johnmatveyev@gmail.com/My Drive/Dictaste Backups/Dictaste-Backup-2026-09-01-nvidia-demo`
- `/Users/john/Library/CloudStorage/GoogleDrive-simpsonvilleai@gmail.com/My Drive/Dictaste Backups/Dictaste-Backup-2026-09-01-nvidia-demo`

## Current blocker for direct Git push

Codex GitHub app is connected to `ascendmaui`, but the Mac command-line Git credential still uses the suspended `johnmatveyev-lab` account. Direct `git push` fails with GitHub 403 until the local `gh` CLI is reauthenticated as `ascendmaui`.

## Safe next command after CLI login

After `gh auth login` is completed for `ascendmaui`, run from the local recovered repo:

```bash
git remote set-url origin https://github.com/ascendmaui/dictaste-web.git
git push -u origin main:dictaste-recovered-2026-09-01
```

Then open a pull request from `dictaste-recovered-2026-09-01` into `main`.

## Security note

No plaintext API keys are committed. The NVIDIA demo key should be stored as a hosting environment variable named `NVIDIA_API_KEY` and rotated before public launch because it was pasted into chat.
