import CoreText
import SwiftUI

enum FontRegistry {
    static func registerBundledFonts() {
        let names = ["Lora-Regular", "Lora-Italic", "Lora-Bold"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "woff2") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    static func lora(size: CGFloat, weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold:
            name = "Lora-Bold"
        default:
            name = "Lora"
        }
        return .custom(name, size: size)
    }
}
