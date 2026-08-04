import CoreText
import SwiftUI

enum FontRegistry {
    static func registerBundledFonts() {
        // Static-instance TTFs: CoreText can't ingest woff2 on iOS (and only
        // incidentally handles it on macOS). The editor embed carries its own
        // woff2 copies - WKWebView's WebContent process can't see these anyway.
        //
        // macOS only: on iOS the Info.plist UIAppFonts array registers these
        // at launch; doing it here too double-registers (GSFont warnings).
        #if os(macOS)
        let names = ["Lora-Regular", "Lora-Italic", "Lora-Bold", "Lora-BoldItalic"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        #endif
    }
}

extension Font {
    static func lora(size: CGFloat, weight: Weight = .regular) -> Font {
        // PostScript instance names, consistently - mixing the family name
        // ("Lora") with PS names resolves on macOS but not reliably on iOS.
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold:
            name = "Lora-Bold"
        default:
            name = "Lora-Regular"
        }
        return .custom(name, size: size)
    }
}
