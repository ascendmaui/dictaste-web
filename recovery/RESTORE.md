# Restore Guide

Last updated: 2026-09-01

## Restore source

1. Copy `Dictaste-Recovered` from either backup location.
2. Open `universal/` for iPhone, Android, browser, Chrome, and PWA work.
3. Open `mac/` for the existing native macOS app.
4. Run `pnpm install` inside `universal/`.
5. Run `pnpm test` and `pnpm build` inside `universal/`.

## Rebuild mobile apps

```bash
cd universal
pnpm install
pnpm build
pnpm cap sync
```

For iOS, open `universal/ios/App/App.xcworkspace` in Xcode.

For Android, open `universal/android` in Android Studio or run:

```bash
cd universal/android
./gradlew :app:assembleDebug
```

## Provider keys

The app does not include provider keys. In Settings, John can paste keys for:

- Dictaste Cloud license key
- Google Gemini API key
- OpenAI API key for ChatGPT API
- xAI API key for Grok
- NVIDIA API key for hosted NIM LLMs

Leave key persistence off unless this is a trusted device.

## Restore macOS app

The notarized macOS installer is preserved in the backup artifacts. The recovered source in `mac/` can also be rebuilt with XcodeGen and Xcode on a Mac.

## Restore Vercel

Do not overwrite the current `dictaste.com` production deployment until a new source repository is connected and a preview deployment is verified.

Current Vercel production deployment:

- Project: `dictaste`
- Deployment: `dpl_9mfX4E4tch8ZR37y4BMwaYFRcy2R`
- Domain: `https://dictaste.com`

