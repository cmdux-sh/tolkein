import CodexBarCore
import Foundation

/// The languages Tolkein can show, stored in `SettingsStore.appLanguage`. `system` follows macOS.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case spanish = "es"
    case portugueseBrazilian = "pt-BR"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case arabic = "ar"
    case italian = "it"
    case vietnamese = "vi"
    case dutch = "nl"
    case turkish = "tr"
    case ukrainian = "uk"
    case russian = "ru"
    case indonesian = "id"
    case polish = "pl"
    case persian = "fa"
    case thai = "th"
    case galician = "gl"
    case catalan = "ca"
    case swedish = "sv"

    var id: String {
        self.rawValue
    }

    var label: String {
        L(self.labelKey, language: self.labelLanguage)
    }

    private var labelLanguage: String {
        switch self {
        case .system, .english:
            "en"
        default:
            self.rawValue
        }
    }

    private var labelKey: String {
        switch self {
        case .system: "language_system"
        case .english: "language_english"
        case .chineseSimplified: "language_chinese_simplified"
        case .chineseTraditional: "language_chinese_traditional"
        case .japanese: "language_japanese"
        case .spanish: "language_spanish"
        case .portugueseBrazilian: "language_portuguese_brazilian"
        case .korean: "language_korean"
        case .german: "language_german"
        case .french: "language_french"
        case .arabic: "language_arabic"
        case .italian: "language_italian"
        case .vietnamese: "language_vietnamese"
        case .dutch: "language_dutch"
        case .turkish: "language_turkish"
        case .ukrainian: "language_ukrainian"
        case .russian: "language_russian"
        case .indonesian: "language_indonesian"
        case .polish: "language_polish"
        case .persian: "language_persian"
        case .thai: "language_thai"
        case .galician: "language_galician"
        case .catalan: "language_catalan"
        case .swedish: "language_swedish"
        }
    }
}

/// The choices of the preferred-currency setting: `auto` (follow the provider, else USD), then every supported code.
enum PreferredCurrencyOption {
    static let codes = ["auto"] + CurrencyExchange.supportedCurrencies

    static func label(for code: String) -> String {
        code == "auto" ? L("currency_auto") : CurrencyExchange.pickerLabel(for: code) ?? code
    }
}
