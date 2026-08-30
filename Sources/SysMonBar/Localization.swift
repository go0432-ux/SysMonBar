import Foundation

/// 使用者可以在選單裡手動切換語言，不用跟著系統語言、也不需要重啟 App。
/// 做法是直接讀取指定 `<code>.lproj/Localizable.strings` 檔案內容，
/// 繞過系統 Bundle.main 在啟動當下就固定好的自動語言判斷，這樣切換才能立即生效。
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    struct LanguageOption: Identifiable, Hashable {
        /// "system" 代表跟隨系統語言；其餘為實際語言代碼，對應 Resources 底下的 .lproj 資料夾
        let code: String
        /// 語言本身的名稱（用該語言自己的文字顯示，例如「繁體中文」），nil 代表「跟隨系統」選項，顯示文字另外用 L(...) 取得
        let displayName: String?
        var id: String { code }
    }

    static let options: [LanguageOption] = [
        LanguageOption(code: "system", displayName: nil),
        LanguageOption(code: "en", displayName: "English"),
        LanguageOption(code: "zh-Hant", displayName: "繁體中文"),
        LanguageOption(code: "zh-Hans", displayName: "简体中文")
    ]

    private static let defaultsKey = "SysMonBar.languageOverride"

    @Published var languageCode: String {
        didSet {
            guard languageCode != oldValue else { return }
            UserDefaults.standard.set(languageCode, forKey: Self.defaultsKey)
            reload()
        }
    }

    private var table: [String: String] = [:]

    private init() {
        self.languageCode = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "system"
        reload()
    }

    private func resolvedCode() -> String {
        if languageCode != "system" { return languageCode }
        return Bundle.main.preferredLocalizations.first ?? "en"
    }

    private func reload() {
        let code = resolvedCode()
        if let dict = loadTable(code: code) {
            table = dict
        } else if let fallback = loadTable(code: "en") {
            table = fallback
        } else {
            table = [:]
        }
        objectWillChange.send()
    }

    private func loadTable(code: String) -> [String: String]? {
        guard let path = Bundle.main.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: "\(code).lproj"
        ), let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            return nil
        }
        return dict
    }

    func string(_ key: String) -> String {
        table[key] ?? key
    }
}

/// 全域快捷函式：L("some.key") 取得目前選定語言的翻譯字串
func L(_ key: String) -> String {
    LocalizationManager.shared.string(key)
}
