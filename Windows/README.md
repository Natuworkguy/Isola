<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../.github/assets/banner-dark.png">
    <img src="../.github/assets/banner-light.png" width="100%" alt="Isola: the same old Dynamic Island, but it's free, open source, and cross-platform.">
  </picture>
</p>

<h1 align="center">Isola for Windows</h1>

<p align="center">
  A Dynamic Island for Windows 10 and 11: a capsule at the top of the screen that springs open into Dynamic Glass<br>
  when you point at it. C# and WPF on .NET 8, written in code (no XAML).
</p>

<p align="center">
  <a href="#install"><b>Install</b></a> &nbsp;·&nbsp;
  <a href="#features"><b>Features</b></a> &nbsp;·&nbsp;
  <a href="../README.md"><b>Isola for Mac</b></a>
</p>

## Install

Download `Isola-Windows-x64-Setup.exe` (or `-arm64`) from the repository's
[Releases](https://github.com/Natuworkguy/Isola/releases), or build it yourself (below). It installs for you alone, so
no administrator rights: Isola goes in `%LocalAppData%\Programs\Isola`, with a Start menu shortcut, and Settings, Apps
uninstalls it. Installing a new version over a running Isola closes it and starts the new one. No .NET needed.

To run it without installing, `Isola-Windows-x64.zip` (or `-arm64`) holds the same single self-contained `Isola.exe`.

Either way the island appears at the top of your main screen; Isola's icon sits in the notification area, with
Settings and Quit. It starts with Windows unless you switch that off in Settings.

Windows SmartScreen may warn about an unsigned app the first time: choose More info, then Run anyway.

## Features

- **Home:** a row of live widgets, and a pencil that arranges them right in the island: drag them into a new order, or
  drag new ones up from the gallery. 24 widgets, from a clock, weather and network speed to a timer, Focus sessions,
  Keep Awake, the moon's phase and a colour picker, and separators, as many as you like, to split them into groups.
- **Media:** every app Windows lists in its media controls (Spotify, browsers, Media Player, VLC and so on). Artwork,
  title, the source app, a seek bar you can drag, and controls. With several apps playing, the Media tab stacks a card
  for each.
- **File Tray:** drop files on the island; drag them back out, open them, share them, zip them to Downloads, or
  convert images. `Isola.exe report.pdf` (or Open with) adds files from anywhere.
- **Basket:** shake a file while dragging it and four drop targets pop up under the pointer: Tray, Share, Convert, Zip.
- **Clipboard:** text, links, colours and images you copy, as cards you can search. Click one to copy it again. Kept
  in `%AppData%\Isola`.
- **System:** CPU, memory, disk and battery rings.
- **Live Activities:**
  - Volume and brightness (laptop screens) as a bar in the island. On Windows 10 Isola can hide the volume overlay.
  - Isola's Timer and Focus sessions ring in the island with Stop and Repeat, and count in the ears while they run,
    like the stopwatch.
  - Clock app alarms and timers appear in the island and Windows' own copy is removed, where Windows grants Isola
    notification access.
  - Green and orange privacy dots while the camera or microphone is in use.
  - Banners for charging and battery, headphones, drives (with Eject), VPNs, downloads, screenshots and recordings,
    going offline and coming back, displays, Caps Lock, the keyboard layout, low storage and Do not disturb. Each has
    its own switch.
- **Live Activities from anything:** `isola://activity` links start an activity with a checklist that ticks off in
  place, or a conversation as it goes (`lines`) with live bars while it listens (`mic`), as on the Mac:

  ```bat
  start "" "isola://activity?id=build&title=Build&steps=done:Fetch|active:Compile|todo:Test"
  start "" "isola://activity/end?id=build"
  ```

- **Gestures and a shortcut:** scroll or swipe down on the island to open it and up on its top edge to close it,
  swipe sideways over the music to skip tracks, or press Ctrl+Alt+A from anywhere.
- **Notifications from anything:** apps and scripts can show a banner with an `isola://notify` link:

  ```bat
  start isola://notify?title=Build%20done^&text=All%20214%20tests%20pass^&symbol=checkmark^&color=green
  ```

  ```powershell
  Start-Process "isola://notify?title=Build%20done&text=All%20214%20tests%20pass&symbol=checkmark&color=green"
  ```

  Parameters are the same as on the Mac: `title`, `text`, `symbol` (common SF Symbol names, or a Segoe Fluent Icons
  code point such as `E73E`), `color`, `duration` (1 to 30 seconds) and `sound` (a sound from `C:\Windows\Media`,
  named without `.wav` or spaces, such as `chimes`, `ding` or `notify`).
- **Look:** a floating capsule or attached to the top edge, in Dynamic Glass or solid black either way, an ambient glow
  from the artwork, and it hides itself during full-screen apps and video. Dynamic Glass blurs whatever is behind the
  island and takes on its colour, denser over bright windows so text stays clear, with a lens of light inside the
  edge, a bright rim and a highlight that follows the pointer.

## Differences from the Mac version

- There is no notch, so the island floats at the top centre of the main screen.
- No Calendar tab: Windows only shares calendar events with packaged Store apps.
- Windows blurs behind whole windows only, so the blur comes from a window of its own kept just under the island and
  cut to its shape. Its very edge is a little less smooth than on the Mac, and where Windows will not blur at all the
  glass uses a deeper tint instead.
- Windows 11's volume overlay cannot be hidden by an app, so that setting only works on Windows 10.
- Windows offers no way to press a Clock alert's Snooze button, so the island's second button opens Clock instead.
- No Focus modes or meeting reminders: Windows has no public way to read them. Do not disturb is shown instead.

## Build

With the .NET 8 SDK, on Windows:

```powershell
.\Windows\build.ps1                       # x64, self-contained: build\win-x64\Isola.exe and build\Isola-Windows-x64.zip
.\Windows\build.ps1 -Runtime win-arm64
.\Windows\build.ps1 -Version 1.2.0
.\Windows\build.ps1 -Installer           # also build\Isola-Windows-x64-Setup.exe, from installer.iss (needs Inno Setup 6)
.\Windows\build.ps1 -FrameworkDependent   # much smaller, needs the .NET 8 Desktop Runtime to run
```

Or from Linux or macOS, with `Windows/build.sh` (`RUNTIME=win-arm64`, `VERSION=1.2.0`, `FRAMEWORK_DEPENDENT=1`). The
project sets `EnableWindowsTargeting`, so it builds anywhere the .NET SDK runs.

GitHub Actions builds both architectures on every push; see Releases in the main README.
