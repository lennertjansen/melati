# 🌰 Noot

Private daily journaling for macOS and iOS.

Native SwiftUI app. SQLCipher-encrypted entries with the key in Keychain. The TipTap editor is bundled as a single-file HTML page (`apple/editor-embed`) and hosted in a `WKWebView`.

## Build (`apple/`)

Requires macOS 14+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.

```sh
cd apple/editor-embed && npm i && npm run build   # build embedded editor
cd .. && xcodegen                                # regenerate Noot.xcodeproj
open Noot.xcodeproj                              # build & run
```

Lint (Biome, covers `apple/editor-embed`):

```sh
pnpm i && pnpm check
```

Shortcuts: ⌘N new entry · ⌘1/⌘2/⌘3 today/entries/calendar · ←/→ flip entries · ⌘[ back · ⌘? help.

## Privacy

No network, no analytics, no accounts. Entries are SQLCipher-encrypted on disk.
