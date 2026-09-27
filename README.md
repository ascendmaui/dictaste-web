# Dictaste Recovered

This is the clean recovery and forward-development repository for Dictaste.

## What is preserved

- `mac/` — the complete native SwiftUI macOS source and its Git history.
- `universal/` — one new client for iPhone, Android/Google, installable Chrome/PWA, and browser use.
- `recovery/` — deployment inventory, checksums, and restore instructions. No secret values are committed.

The existing production website at `https://dictaste.com` is intentionally not deployed from this repository yet. Its live Vercel deployment remains untouched while the unavailable private GitHub source is recovered or replaced.

## Universal client

The universal client supports:

- Browser speech recognition with a typed-input fallback.
- Native iOS and Android speech recognition through Capacitor.
- Local cleanup that works without an account.
- Dictaste managed polish through the existing `/api/v1/polish` contract.
- Bring-your-own Google Gemini polish using the current Interactions API.
- Bring-your-own ChatGPT API, xAI Grok, and NVIDIA LLM polish.
- Copy, share, read-aloud, history, offline install, and responsive mobile UI.

See `universal/README.md` for build commands.

## Security

API keys, license keys, and Vercel environment values are never committed. The backup process stores any recovered secret values only in a separate encrypted archive.
