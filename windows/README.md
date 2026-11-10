# Notchbeat for Windows

A native Dynamic Island for Windows with YouTube Music / System Media integration, app switching bubbles, clipboard history, calendar countdowns, system stats, file parking, quick notes, and AI agent monitoring.

---

## Features Ported to Windows

1. **Top-Center Floating Dynamic Island**: Borderless, top-most pill window at the top center of the screen that expands smoothly on hover into tabs.
2. **Media Integration (Zero Config)**: Powered by Windows SMTC (`GlobalSystemMediaTransportControlsSessionManager`). Natively supports Chrome, YouTube Music, Spotify, Edge, and all Windows media players with title, artist, live position, duration, and full transport controls.
3. **App Switcher Bubbles**: Enumerate open windows and switch directly to running apps.
4. **Clipboard History**: Remembers your last 60 copied items (text, files, links), safely ignoring sensitive password manager formats.
5. **Calendar**: Displays upcoming meetings with instant join buttons for Zoom, Microsoft Teams, Google Meet, and Webex.
6. **System Stats & Battery**: Live CPU, RAM, Network I/O, and Battery monitoring.
7. **Bluetooth Device Monitoring**: Battery levels for connected Bluetooth devices (AirPods, headphones, keyboards, mice).
8. **File Tray (Shelf)**: Drag and drop files onto the island to park them and drag them out anywhere.
9. **Scratchpad Notes**: Quick notes that auto-save as you type.
10. **Coding Agent Monitor**: Live status tracking of local Claude Code and Codex terminal sessions.

---

## How to Build the `.exe`

### Option 1: On Any Windows PC with .NET 8 SDK
Open Command Prompt / PowerShell in the `windows` folder and run:
```bat
build.bat
```
or manually:
```bash
dotnet publish Notchbeat/Notchbeat.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -p:PublishTrimmed=true -o build
```
This generates a single self-contained executable:
```
windows/build/Notchbeat.exe
```

### Option 2: Via GitHub Actions (Automated Cloud Build)
The repository includes `.github/workflows/build-windows.yml`. When you push to GitHub or click **Run workflow** under the Actions tab, GitHub will build `Notchbeat.exe` in the cloud on a Windows runner and provide it as a direct download artifact!

