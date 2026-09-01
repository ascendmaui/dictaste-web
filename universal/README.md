# Dictaste Universal

One shared client for:

- iPhone and iPad through Capacitor iOS.
- Android and Google Play through Capacitor Android.
- Chrome, Edge, Safari, and installable PWA use.
- Google Gemini polish through the current Gemini Interactions API.
- ChatGPT API and xAI Grok polish through their Responses APIs.
- NVIDIA LLM polish through hosted NVIDIA NIM chat completions.
- The existing Dictaste managed-polish API.

## Run locally

```bash
pnpm install
pnpm dev
```

## Verify

```bash
pnpm test
pnpm build
```

## Native shells

The generated `ios/` and `android/` projects are committed so a new Mac can restore them without recreating configuration.

```bash
pnpm cap:sync
pnpm cap:ios
pnpm cap:android
```

Apple signing and Google Play signing stay outside source control. Store credentials must be supplied through Xcode/Google Play when publishing.

## Keys

The app contains no API keys. Users can select private local cleanup, provide a Dictaste license, or provide their own Gemini, OpenAI, xAI, or NVIDIA key. Key persistence is opt-in and remains device-local.
