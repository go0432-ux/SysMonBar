# SysMonBar

一個純原生、無相依套件的 macOS 選單列系統監控工具，即時顯示 CPU / 記憶體 / 硬碟使用率。

## 特色

- **原生 SwiftUI `MenuBarExtra`**。記憶體用量依面板狀態、框架快取與使用時間而變，測量口徑與本機觀測見下方說明。
- **不 spawn 子行程**做核心監控：CPU / 記憶體用 Mach API (`host_statistics` / `host_statistics64`) 直接讀，硬碟用 `FileManager`，比呼叫 `top` / `vm_stat` / `df` 更省資源。（Top-5 記憶體程式清單例外，這項本來就需要讀行程列表，用一次輕量的 `ps` 呼叫取得。）
- **選單列顯示可自訂**：CPU + 記憶體同時顯示，或只顯示其中一項——在設定裡選（見下方）。
- **60 分鐘歷史走勢圖**（Swift Charts）：CPU / 記憶體 / 硬碟讀取速度 / 硬碟寫入速度，各自獨立一條走勢圖（像 Activity Monitor 那樣分開排列），彼此不會重疊；點色塊標籤可單獨隱藏／顯示某一項，預設四項都顯示。硬碟走勢圖顯示的是即時讀寫速度（MB/s、KB/s），不是容量使用率。
- **記憶體使用量最高的 5 個程式**：即時列出，附程式名稱、佔用 MB 數與佔總記憶體的百分比，跟其他數據共用同一個計時器，一樣依照「刷新頻率」設定更新。
- **刷新頻率可調**：1 / 2 / 5 / 10 / 30 / 60 秒，預設 **10 秒**，設定會存到 UserDefaults，下次啟動自動沿用。
- **多國語言**：正體中文／簡體中文／English，可在選單內的「語言」選項直接切換，不用跟著系統語言、也不用重開 App；選「跟隨系統」則自動依照 macOS 系統語言。
- **選單內建「解除安裝」**：點下去直接移除 `/Applications/SysMonBar.app` 並結束程式，不用回終端機（沒有二次確認，請小心點擊）。
- 沒有 Dock 圖示（`LSUIElement`），純選單列常駐。

## 下載安裝（一般使用者）

前往 [Releases](../../releases) 頁面下載最新的 `SysMonBar.dmg`：

1. 打開 dmg，把 `SysMonBar.app` 拖進 `Applications` 捷徑。
2. 因為這是未經 Apple 官方公證（notarize）的個人專案，第一次開啟時 macOS 可能會擋下「無法確認開發者」的警告——**在 Finder 裡對 App 按右鍵 → 開啟**，再按一次「開啟」即可（之後就能正常雙擊開啟）。

## 從原始碼建置（開發者）

需求：macOS 13 (Ventura) 或以上、Xcode Command Line Tools（沒有的話跑 `xcode-select --install`）。

```bash
git clone https://github.com/<你的帳號>/SysMonBar.git
cd SysMonBar
chmod +x build.sh install.sh make-dmg.sh uninstall.sh

./build.sh          # 編譯並在 dist/SysMonBar.app 產生標準 .app（含多國語言資源）
./install.sh         # 選用：自動複製到 /Applications 並開啟
./make-dmg.sh         # 選用：打包成可分享的 dist/SysMonBar.dmg
```

`build.sh` 只會在本機做 ad-hoc code sign（讓自己能開啟），不會做 Apple 公證。

## 移除

**方式一：選單列內建按鈕（推薦）**
點選單列圖示 → 拉到最下面「解除安裝 SysMonBar」→ 直接執行，自動關閉程式並刪除 App（沒有二次確認，請小心點擊）。

**方式二：終端機**
```bash
./uninstall.sh
```

## 設定選項

記憶體列表預設顯示前五名 App。點「展開全部」會顯示所有 App，並在下方列出未歸屬 App 的背景及獨立行程，含名稱、PID 與 RSS 用量。App 與背景行程各依用量排序；同一 App 內的 Helper 不會重複列出。點「收合至前 5 名」可還原，刷新時維持目前展開狀態。

前五名列表按 App 合併同一個外層 `.app` 內的主程式與 Helper，再依 RSS 合計排名，並顯示行程數。未進入前五名的 App、獨立行程與服務都計入「其他行程」。這些 RSS 估算可能重複包含共享記憶體，不能相加當成總 RAM 用量。外層 App 目錄以外的 Helper 無法僅靠路徑歸屬，會列入其他行程。

上方 RAM 分類以 Mach API 讀取，總量為「程式記憶體（匿名頁扣除可清除部分）＋系統有線記憶體＋壓縮資料的實體佔用」，不含檔案快取。此估算取代舊版使用 active 頁的算法，數值可能改變；並非活動監視器數字的保證副本。上方分類使用 GiB；App 與背景行程列表採 1024 MB＝1 GB 換算，達到 1024 MB 自動顯示 GB，最多一位小數。

點擊 App 右側的 ⓧ 按鈕，再確認 App 名稱及行程數，即可向主 App 要求正常退出。未儲存的內容可能遺失。沒有可識別主 App 的項目、其他使用者的 App 與 SysMonBar 無法在此結束。列表於下次刷新更新；App 可能拒絕退出或自動重啟，本工具不強制結束整組 PID。

在選單裡可以調整：

- **刷新頻率**：1 / 2 / 5 / 10 / 30 / 60 秒（預設 10 秒）——所有數據（CPU、記憶體、硬碟讀寫、Top-5 記憶體程式）都跟著這個頻率一起更新
- **選單列顯示**：CPU + 記憶體 / 只顯示 CPU / 只顯示記憶體
- **語言**：跟隨系統 / English / 繁體中文 / 简体中文，選了立即生效
- **走勢圖顯示哪幾條線**：點圖表右上角的色塊標籤即可單獨切換 CPU / MEM / READ / WRITE

## 開機自動啟動（選用）

系統設定 → 一般 → 登入項目 → 加入 SysMonBar.app。

## 專案結構

```
SysMonBar/
├── Package.swift                         Swift Package 定義
├── Sources/SysMonBar/
│   ├── SysMonBarApp.swift                選單列 UI、歷史走勢圖、Top-5 記憶體、設定、解除安裝
│   ├── SystemMonitor.swift               CPU/記憶體/硬碟讀取、Top-5 程式、歷史資料、設定持久化
│   └── Localization.swift                App 內語言切換（不依賴系統語言，即選即生效）
├── Resources/
│   ├── en.lproj/Localizable.strings      English
│   ├── zh-Hant.lproj/Localizable.strings 正體中文
│   └── zh-Hans.lproj/Localizable.strings 简体中文
├── build.sh                              編譯 + 打包成 dist/SysMonBar.app
├── install.sh                            複製到 /Applications 並開啟
├── make-dmg.sh                           打包成 dist/SysMonBar.dmg（給 GitHub Releases 用）
├── uninstall.sh                          終端機手動移除
└── .github/workflows/build.yml           CI：push tag (v*.*.*) 自動建置並發佈 Release
```

## 發佈新版本（維護者）

```bash
git tag v1.0.0
git push origin v1.0.0
```
GitHub Actions 會自動建置 `SysMonBar.dmg` 並附加到對應的 Release。

## 新增語言

在 `Resources/` 下新增 `<語言代碼>.lproj/Localizable.strings`（複製現有檔案翻譯即可），並在 `build.sh` 的 `CFBundleLocalizations` 陣列裡加上對應語言代碼。

## 自訂

- 歷史走勢圖時間窗（目前 60 分鐘）：改 `SystemMonitor.swift` 裡的 `historyWindow`。
- 可選的刷新頻率選項：改 `SystemMonitor.availableIntervals`。
- Top-5 記憶體程式清單筆數（目前 5 筆）：改 `updateTopMemoryProcesses()` 裡的 `head -n 5`。

## 測試

關閉面板時只持續收集選單列數值與 60 分鐘歷史，不掃描行程列表；重新開啟面板時立即更新 App 與背景行程。列表可見時仍依刷新頻率更新。首次啟動即開始核心監控，不必先點開面板。

同日整理後重啟、尚未打開面板，以 `proc_pid_rusage` 每 2 秒讀取一次，共 5 次，physical footprint 為 15.27–15.28 MiB，resident memory 為 68.66–68.67 MiB。先前已使用一段時間的行程，5 次 physical footprint 取樣約 47.56 MiB。兩者的使用時間和面板狀態不同，不可據此聲稱固定降幅。RSS 與 physical footprint 是不同口徑；開啟圖表或展開列表可能增加記憶體。原生視窗測試驗證保留但隱藏的面板會停掃，歷史仍繼續累積。

2026-11-23 在 Apple M4 Max、macOS 26.5.1，以 `ps` 對正在執行的版本 `6668c2f` 每 5 秒讀取一次 RSS，共 6 次、歷時 25 秒，結果為 109.6–109.7 MB（此處 1 MB＝1024 KiB）。這是單機短時觀測，未控制視窗開關狀態；並非活動監視器的「記憶體」欄位計算方式，也不代表所有 Mac 或長時間使用的固定值。已移除先前未有當前版本量測支持的「10–20 MB」說法。

記憶體分類、App 合併與結束保護的測試可用 `sh Tests/run.sh` 執行，僅需 macOS Command Line Tools。測試僅建立及結束自己的暫存 sleep 行程，不會退出使用中的 App。

## License

[MIT](LICENSE)
