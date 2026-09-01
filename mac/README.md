# Dictaste for macOS

Native menu bar app — system-wide dictation + highlight-to-speak.

**Product site:** https://dictaste.vercel.app  
**Developer free plan:** star https://github.com/johnmatveyev-lab/dictaste then unlock at https://dictaste.vercel.app/developers/setup  

## Install (developers)

```bash
git clone https://github.com/johnmatveyev-lab/dictaste-mac.git
cd dictaste-mac
brew install xcodegen   # once
xcodegen generate
chmod +x scripts/install_local.sh
./scripts/install_local.sh
# → /Applications/Dictaste.app
```

Full guide: https://github.com/johnmatveyev-lab/dictaste/blob/main/docs/INSTALL_MAC.md

## Permissions

- Microphone  
- Accessibility  
- Speech Recognition  

## After install

1. Menu bar → **Account & Settings…**  
2. Paste license (`dt_live_…`) from developer setup  
3. Paste your OpenAI-compatible API key (Developer plan)  
4. Hold **fn 🌐** to dictate · highlight text to hear it  

## Note on names

Xcode target/product may still use the historical target name `FlowDictate` internally; the installed app is **Dictaste.app** with display name Dictaste. Bundle id remains stable for Accessibility TCC.
