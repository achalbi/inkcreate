# Inkcreate Capacitor Speech Recognition Plugin

Android-only Capacitor bridge for ML Kit GenAI Speech Recognition.

Current behavior:

- Downloads a saved Inkcreate voice-note audio file using the current web session cookie.
- Runs ML Kit speech recognition on-device.
- Returns the transcript text to the web layer.

Notes:

- Requires Android API 26+ because the ML Kit speech-recognition SDK does.
- Inkcreate uses `basic` mode by default for the broadest device coverage.
