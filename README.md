# LocalVoice

LocalVoice is a lightweight, native macOS dictation app. Press **Fn** to start or stop recording, then the app transcribes the saved audio with Deepgram, copies the result, and can optionally send **⌘V** to the focused app.

## Requirements

- macOS 13 or later
- Apple silicon Mac (the build currently targets `arm64`)
- Xcode Command Line Tools, including Swift, `codesign`, and `openssl`
- A Deepgram API key for transcription

## Install from source

This repository is private. You need collaborator access to clone it or download its source archive.

```sh
git clone https://github.com/kartik-py12/LocalVoice.git
cd LocalVoice
./Scripts/setup-signing.sh
./Scripts/build-app.sh
```

Run `setup-signing.sh` once on each Mac. It creates a local signing identity in that Mac's login Keychain. Then `build-app.sh` compiles the app, installs it at `~/Applications/LocalVoice.app`, and opens it. For later updates, pull the latest code and rerun `./Scripts/build-app.sh`; it reuses the signing identity, restarts an idle app, and refuses to update while an audio file is open.

## First-run setup

1. Open **Settings** in LocalVoice, enter your Deepgram API key, and save it. The app stores it in macOS Keychain; no API key belongs in this repository.
2. Enable **Fn shortcut**. In **System Settings → Privacy & Security → Input Monitoring**, allow `LocalVoice` from `~/Applications/LocalVoice.app` if macOS asks.
3. Allow microphone access when prompted the first time you record.
4. Optional: enable **Auto-paste transcripts**. This sends ⌘V without pressing Return and requires the separate **Accessibility** permission for LocalVoice.

## Use

- Press **Fn** once to start recording and again to stop and transcribe.
- Or use the recording button in the app or its recording HUD.
- Successful transcripts are copied to the clipboard. With auto-paste on, LocalVoice sends ⌘V to the external app that remains focused after transcription.
- Open **History** to review transcripts and play or locate saved recordings. Delete a history item to remove its transcript and audio file.

Audio and transcript history stay under `~/Library/Application Support/LocalVoice/`. Audio is uploaded to Deepgram over HTTPS when transcription is requested. LocalVoice uses Deepgram Nova-3 multilingual mode with smart formatting and punctuation.

## Build and test

Build and install:

```sh
./Scripts/build-app.sh
```

Run the deterministic recording-state check:

```sh
swiftc -parse-as-library -swift-version 5 Sources/RecordingStartGate.swift Tests/RecordingStartGateTests.swift -o /tmp/LocalVoice-state-check
/tmp/LocalVoice-state-check
```

## Downloading a ready-to-run app

GitHub provides source archives for this repository, but this project does not currently publish a ready-to-run `.app`. The build uses a local self-signed identity, which is intended for building on your own Mac. Direct distribution to other Macs requires a Developer ID signature and Apple notarization; see [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Project layout

- `Sources/` — app UI, recording/history state, Fn monitoring, and Deepgram requests
- `Scripts/setup-signing.sh` — creates a per-Mac local signing identity
- `Scripts/build-app.sh` — builds, signs, installs, and opens LocalVoice
- `Scripts/make-icon.swift` — generates the app icon
- `Tests/` — deterministic recording-state check

## License

MIT. See [LICENSE](LICENSE).
