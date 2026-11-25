// SPDX-License-Identifier: MIT
import Foundation

/// The rows of every search layout, copied from the keyboards iOS draws for each language (ADR 0066).
enum SearchKeyboardLayouts {
    /// Split on the space scalar, not on `Character`: a space before a combining mark (Thai ุ, Devanagari ि) is
    /// one grapheme with it, so a `Character` split would merge two keys.
    private static func keys(_ line: String) -> [String] {
        line.unicodeScalars.split(separator: " ").map { String(String.UnicodeScalarView($0)) }
    }

    private static func grid(_ lines: String...) -> [[String]] {
        lines.map(keys)
    }

    /// iOS's long-press accents on a Latin keyboard.
    static let latinVariants: [String: [String]] = [
        "a": keys("à á â ä æ ã å ā"), "c": keys("ç ć č"), "e": keys("è é ê ë ē ė ę"), "i": keys("î ï í ī į ì"),
        "l": keys("ł"), "n": keys("ñ ń"), "o": keys("ô ö ò ó œ ø ō õ"), "s": keys("ß ś š"), "u": keys("û ü ù ú ū"),
        "y": keys("ÿ"), "z": keys("ž ź ż"), "g": keys("ğ"), "d": keys("ð")
    ]

    static let qwerty = SearchKeyboardLayout(
        id: "qwerty", languageCode: "en",
        rows: grid("q w e r t y u i o p", "a s d f g h j k l", "z x c v b n m"), variants: latinVariants
    )
    static let spanish = SearchKeyboardLayout(
        id: "spanish", languageCode: "es",
        rows: grid("q w e r t y u i o p", "a s d f g h j k l ñ", "z x c v b n m"), variants: latinVariants
    )
    static let azerty = SearchKeyboardLayout(
        id: "azerty", languageCode: "fr",
        rows: grid("a z e r t y u i o p", "q s d f g h j k l m", "w x c v b n"), variants: latinVariants
    )
    static let german = SearchKeyboardLayout(
        id: "german", languageCode: "de",
        rows: grid("q w e r t z u i o p ü", "a s d f g h j k l ö ä", "y x c v b n m"), variants: latinVariants
    )
    static let qwertz = SearchKeyboardLayout(
        id: "qwertz", languageCode: "cs",
        rows: grid("q w e r t z u i o p", "a s d f g h j k l", "y x c v b n m"), variants: latinVariants
    )
    static let swedish = SearchKeyboardLayout(
        id: "swedish", languageCode: "sv",
        rows: grid("q w e r t y u i o p å", "a s d f g h j k l ö ä", "z x c v b n m"), variants: latinVariants
    )
    static let danish = SearchKeyboardLayout(
        id: "danish", languageCode: "da",
        rows: grid("q w e r t y u i o p å", "a s d f g h j k l æ ø", "z x c v b n m"), variants: latinVariants
    )
    static let norwegian = SearchKeyboardLayout(
        id: "norwegian", languageCode: "nb",
        rows: grid("q w e r t y u i o p å", "a s d f g h j k l ø æ", "z x c v b n m"), variants: latinVariants
    )
    static let turkish = SearchKeyboardLayout(
        id: "turkish", languageCode: "tr",
        rows: grid("q w e r t y u ı o p ğ ü", "a s d f g h j k l ş i", "z x c v b n m ö ç"), variants: latinVariants
    )
    static let russian = SearchKeyboardLayout(
        id: "russian", languageCode: "ru",
        rows: grid("й ц у к е н г ш щ з х", "ф ы в а п р о л д ж э", "я ч с м и т ь б ю"),
        variants: ["е": ["ё"], "ь": ["ъ"]]
    )
    static let ukrainian = SearchKeyboardLayout(
        id: "ukrainian", languageCode: "uk",
        rows: grid("й ц у к е н г ш щ з х ї", "ф і в а п р о л д ж є", "я ч с м и т ь б ю"),
        variants: ["г": ["ґ"], "ь": ["ъ"]]
    )
    static let greek = SearchKeyboardLayout(
        id: "greek", languageCode: "el",
        rows: grid("ς ε ρ τ υ θ ι ο π", "α σ δ φ γ η ξ κ λ", "ζ χ ψ ω β ν μ"),
        variants: [
            "ε": ["έ"], "α": ["ά"], "η": ["ή"], "ι": keys("ί ϊ ΐ"), "ο": ["ό"], "υ": keys("ύ ϋ ΰ"), "ω": ["ώ"]
        ]
    )
    static let hebrew = SearchKeyboardLayout(
        id: "hebrew", languageCode: "he",
        rows: grid("ק ר א ט ו ן ם פ", "ש ד ג כ ע י ח ל ך ף", "ז ס ב ה נ מ צ ת ץ"),
        isRTL: true, isCased: false, deleteRow: 0
    )
    static let arabic = SearchKeyboardLayout(
        id: "arabic", languageCode: "ar",
        rows: grid("ض ص ث ق ف غ ع ه خ ح ج د", "ش س ي ب ل ا ت ن م ك ط", "ذ ئ ء ؤ ر ى ة و ز ظ"),
        isRTL: true, isCased: false, variants: ["ا": keys("أ إ آ"), "ي": keys("ى ئ"), "ه": ["ة"], "و": ["ؤ"]]
    )
    static let persian = SearchKeyboardLayout(
        id: "persian", languageCode: "fa",
        rows: grid("ض ص ث ق ف غ ع ه خ ح ج چ", "ش س ی ب ل ا ت ن م ک گ", "ظ ط ژ ز ر ذ د پ و"),
        isRTL: true, isCased: false, variants: ["ا": keys("آ أ"), "ی": ["ئ"], "ه": ["ۀ"]]
    )
    static let korean = SearchKeyboardLayout(
        id: "korean", languageCode: "ko",
        rows: grid("ㅂ ㅈ ㄷ ㄱ ㅅ ㅛ ㅕ ㅑ ㅐ ㅔ", "ㅁ ㄴ ㅇ ㄹ ㅎ ㅗ ㅓ ㅏ ㅣ", "ㅋ ㅌ ㅊ ㅍ ㅠ ㅜ ㅡ"),
        shiftedRows: grid("ㅃ ㅉ ㄸ ㄲ ㅆ ㅛ ㅕ ㅑ ㅒ ㅖ", "ㅁ ㄴ ㅇ ㄹ ㅎ ㅗ ㅓ ㅏ ㅣ", "ㅋ ㅌ ㅊ ㅍ ㅠ ㅜ ㅡ"),
        isCased: false, composesHangul: true
    )
    /// Kedmanee, the layout iOS's Thai keyboard uses.
    static let thai = SearchKeyboardLayout(
        id: "thai", languageCode: "th",
        rows: grid(
            "ๅ / - ภ ถ ุ ึ ค ต จ ข ช", "ๆ ไ ำ พ ะ ั ี ร น ย บ ล ฃ", "ฟ ห ก ด เ ้ ่ า ส ว ง", "ผ ป แ อ ิ ื ท ม ใ ฝ"
        ),
        shiftedRows: grid(
            "+ ๑ ๒ ๓ ๔ ู ฿ ๕ ๖ ๗ ๘ ๙", "๐ \" ฎ ฑ ธ ํ ๊ ณ ฯ ญ ฐ , ฅ", "ฤ ฆ ฏ โ ฌ ็ ๋ ษ ศ ซ .", "( ) ฉ ฮ ฺ ์ ? ฒ ฬ ฦ"
        ),
        isCased: false
    )
    /// InScript, the standard Devanagari layout.
    static let hindi = SearchKeyboardLayout(
        id: "hindi", languageCode: "hi",
        rows: grid("ौ ै ा ी ू ब ह ग द ज ड", "ो े ् ि ु प र क त च ट", "ॆ ं म न व ल स य ़"),
        shiftedRows: grid("औ ऐ आ ई ऊ भ ङ घ ध झ ढ", "ओ ए अ इ उ फ ऱ ख थ छ ठ", "ऎ ँ ण ऩ ऴ ळ श ष ञ"),
        isCased: false
    )
}
