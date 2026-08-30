# SysMonBar

A native, dependency-free macOS menu bar system monitor that displays real-time CPU, memory, and disk usage.

## Features

- **Native SwiftUI `MenuBarExtra`** — not Electron; typical resident memory usage is only 10–20 MB.
- **No spawned child processes for core monitoring.** CPU and memory use the Mach APIs (`host_statistics` / `host_statistics64`) directly, while disk capacity uses `FileManager`, making it lighter than calling `top`, `vm_stat`, or `df`. The Top 5 memory-process list is the exception: it uses one lightweight `ps` call to read the process list.
- **Customizable menu bar display:** show CPU and memory together, CPU only, or memory only.
- **60-minute history charts** built with Swift Charts. CPU, memory, disk read speed, and disk write speed each have their own chart, like Activity Monitor. Toggle any metric individually from its colored label. Disk charts show live throughput (MB/s or KB/s), not disk-capacity usage.
- **Top 5 memory-consuming processes** with process name, memory use in MB, and percentage of total memory. They refresh on the same timer as the other metrics.
- **Adjustable refresh interval:** 1 / 2 / 5 / 10 / 30 / 60 seconds; the default is **10 seconds**. Your choice is saved in UserDefaults and restored on the next launch.
- **Languages:** Traditional Chinese, Simplified Chinese, and English. Switch directly from the menu without restarting; alternatively, follow the system language.
- **Built-in uninstall action:** remove `/Applications/SysMonBar.app` and quit directly from the menu. There is no confirmation dialog, so use it carefully.
- **No Dock icon** (`LSUIElement`): it lives entirely in the menu bar.

## Download and install

Download the latest `SysMonBar.dmg` from the [Releases](../../releases) page.

1. Open the DMG and drag `SysMonBar.app` to the `Applications` shortcut.
2. This personal project is not Apple-notarized, so macOS may show an “unidentified developer” warning the first time you open it. In Finder, Control-click the app, choose **Open**, then choose **Open** again. Future launches will work normally.

## Build from source

Requirements: macOS 13 (Ventura) or later, plus Xcode Command Line Tools. If needed, install them with `xcode-select --install`.

```bash
git clone https://github.com/<your-account>/SysMonBar.git
cd SysMonBar
chmod +x build.sh install.sh make-dmg.sh uninstall.sh

./build.sh          # Build a standard app bundle at dist/SysMonBar.app, including localization resources
./install.sh        # Optional: copy the app to /Applications and launch it
./make-dmg.sh       # Optional: package dist/SysMonBar.dmg for sharing
```

`build.sh` applies only an ad-hoc local code signature so you can open the app. It does not notarize the app with Apple.

## Uninstall

**Option 1: from the menu bar (recommended)**

Click the menu bar icon, scroll to the bottom, then select **Uninstall SysMonBar**. It quits the app and removes it directly, without confirmation.

**Option 2: from Terminal**

```bash
./uninstall.sh
```

## Settings

The menu lets you configure:

- **Refresh interval:** 1 / 2 / 5 / 10 / 30 / 60 seconds (10 seconds by default). All metrics—CPU, memory, disk I/O, and Top 5 memory processes—refresh together.
- **Menu bar display:** CPU + memory, CPU only, or memory only.
- **Language:** Follow System, English, Traditional Chinese, or Simplified Chinese. Changes apply immediately.
- **Chart metrics:** use the colored labels at the top-right of the chart to toggle CPU / MEM / READ / WRITE independently.

## Launch at login (optional)

Go to **System Settings → General → Login Items** and add `SysMonBar.app`.

## Project layout

```
SysMonBar/
├── Package.swift                         Swift Package definition
├── Sources/SysMonBar/
│   ├── SysMonBarApp.swift                Menu bar UI, history charts, Top 5 processes, settings, and uninstall
│   ├── SystemMonitor.swift               CPU/memory/disk monitoring, process data, history, and persisted settings
│   └── Localization.swift                In-app language switching, independent of system language
├── Resources/
│   ├── en.lproj/Localizable.strings      English
│   ├── zh-Hant.lproj/Localizable.strings Traditional Chinese
│   └── zh-Hans.lproj/Localizable.strings Simplified Chinese
├── build.sh                              Build and package dist/SysMonBar.app
├── install.sh                            Copy to /Applications and launch
├── make-dmg.sh                           Package dist/SysMonBar.dmg for GitHub Releases
├── uninstall.sh                          Manual uninstall from Terminal
└── .github/workflows/build.yml           CI: build and publish a release when a v*.*.* tag is pushed
```

## Publish a new version

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions automatically builds `SysMonBar.dmg` and attaches it to the corresponding release.

## Add a language

Add `<language-code>.lproj/Localizable.strings` under `Resources/` by copying and translating an existing file. Then add that language code to the `CFBundleLocalizations` array in `build.sh`.

## Customize

- History-chart window (currently 60 minutes): change `historyWindow` in `SystemMonitor.swift`.
- Available refresh intervals: change `SystemMonitor.availableIntervals`.
- Number of Top 5 memory processes: change `head -n 5` in `updateTopMemoryProcesses()`.

## License

[MIT](LICENSE)
