# Dictaste Recovery Status

Last updated: 2026-09-01

## Current state

- The production website at `https://dictaste.com` is live and was not overwritten.
- Vercel project `dictaste` was inspected without changing production.
- Native macOS source was recovered from `/Users/john/dictaste-mac`.
- A new universal client was created for iOS, Android, browser, Chrome, and installable PWA use.
- The universal app supports local cleanup, Dictaste Cloud, Google Gemini, ChatGPT API, xAI Grok, and NVIDIA LLM providers.
- NVIDIA also has a server-side demo endpoint for the free version, using `NVIDIA_API_KEY` from hosting environment variables.
- GitHub is connected as `ascendmaui`; recovery PR 1 is open at `https://github.com/ascendmaui/dictaste-web/pull/1`.
- No API keys, license keys, signing secrets, or Vercel secret values are committed.

## Recovered source

- `mac/`: native SwiftUI macOS app source, preserved with Git history when this repository is initialized from the recovery process.
- `universal/`: React, TypeScript, Vite, Capacitor, and PWA client for iPhone, Android, browser, and Chrome.
- `recovery/`: deployment inventory, restore notes, and checksums.

## Known gaps

- The suspended GitHub account blocks access to the old private web source repository.
- The old Windows source was not found locally during recovery.
- The existing notarized macOS installer is preserved as an artifact, but new notarization requires Apple account access.
- Live OpenAI/xAI/Gemini smoke tests require John to paste or save provider API keys.
- The NVIDIA key pasted into chat should be rotated after the demo because chat is not an ideal permanent secret vault.

## Verified builds

- Universal web build: passed.
- Universal unit tests: passed.
- iOS simulator build: passed.
- Android debug APK build: passed.
- Existing notarized macOS app: preserved and installed at `/Applications/Dictaste.app`.
