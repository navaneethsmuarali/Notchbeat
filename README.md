# 🎵 Notchbeat

**A Dynamic Island for YouTube Music & System Control — Available on macOS and Windows.**

A sleek, pill-shaped Dynamic Island at the top center of your screen that shows what's playing in YouTube Music, expanding on hover to give you complete playback controls, running app switcher bubbles, clipboard history, upcoming calendar meetings with 1-click join, live system & battery stats, file drop shelf, quick notes, and AI coding agent activity tracking.

---

## 🪟 Windows Installation

### Option 1: Download the Pre-built Executable (Recommended)
You don't need to install any developer tools or compilers!
1. Go to the **[Actions](../../actions)** tab in this GitHub repository.
2. Click on the latest **Build Windows Exe** workflow run.
3. Under **Artifacts** at the bottom of the page, download **`Notchbeat-Windows-x64`**.
4. Extract the zip and run **`Notchbeat.exe`**.

> **Note:** The Windows executable is completely self-contained — no .NET runtime or dependencies required.

### Option 2: Build from Source on Windows
1. Make sure the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) is installed.
2. In the `windows` folder, double-click:
   ```cmd
   build.bat
   ```
   Or run in terminal:
   ```cmd
   dotnet publish Notchbeat/Notchbeat.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o build
   ```
3. Your standalone executable will be at `windows\build\Notchbeat.exe`.

---

## 🍎 macOS Installation

### Requirements
- macOS 14 (Sonoma) or newer (Apple Silicon & Intel universal binary)
- Google Chrome with YouTube Music (`music.youtube.com`)

### Install
1. Run `./build.sh install` in the terminal to compile and install into `/Applications/Notchbeat.app`.
2. In Google Chrome menu bar, enable:  
   **View → Developer → Allow JavaScript from Apple Events**
3. When prompted, grant Notchbeat permission to control Chrome.

---

## ✨ Features

- **Floating Dynamic Island:** Top-center pill that smoothly expands on hover into tabs.
- **YouTube Music & System Media Integration:**
  - Track title, artist, live position, scrubber bar, and album artwork.
  - Windows: Zero-setup integration via native Windows System Media Transport Controls (SMTC) — works across Chrome, Edge, Spotify, and YouTube Music.
  - macOS: Direct Chrome JavaScript bridge.
- **App Switcher Bubbles:** Shows round bubbles for your currently open applications and windows. Click to instantly switch to any app or window.
- **Clipboard History:** Remembers your last 60 copied texts, links, and files. Ignores sensitive password manager entries. Global hotkey `Ctrl+Shift+V` (Windows) / `Cmd+Shift+V` (macOS).
- **Calendar:** Displays upcoming meetings with instant green **Join** button for Google Meet, Zoom, Microsoft Teams, and Webex.
- **System Stats & Battery:** Real-time CPU, RAM, Network I/O graphs, and Battery percentage.
- **Bluetooth Device Monitoring:** Battery percentage and connection alerts for AirPods, headphones, keyboards, and mice.
- **File Tray (Shelf):** Drag and drop files onto the island to park them temporarily and drag them back out anywhere.
- **Scratchpad Notes:** Quick notes area that auto-saves as you type.
- **AI Coding Agent Monitor:** Live detection and alerts for local Claude Code and Codex terminal sessions.
- **Floating MiniPlayer:** Picture-in-picture draggable mini player.
