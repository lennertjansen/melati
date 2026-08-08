# 🌸 Melati

Private daily journaling app I made for me and my gf. Built for macOS and iOS.

Native SwiftUI app. [SQLCipher](https://github.com/sqlcipher/sqlcipher)-encrypted entries with the key in Keychain. [TipTap](https://github.com/ueberdosis/tiptap) editor is bundled as a single-file HTML page (`apple/editor-embed`) and hosted in a `WKWebView`.

## Build (`apple/`)

Requires macOS 14+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.

```sh
cd apple/editor-embed && npm i && npm run build   # build embedded editor
cd .. && xcodegen                                # regenerate Melati.xcodeproj
open Melati.xcodeproj                              # build & run
```

Lint (Biome, covers `apple/editor-embed`):

```sh
pnpm i && pnpm check
```

Shortcuts:
- ⌘N new entry
- ⌘1/⌘2/⌘3 today/entries/calendar
- ←/→ flip entries
- ⌘[ back
- ⌘? help

## Privacy

Entries are SQLCipher-encrypted on disk. Sync goes only through your own iCloud, which the developer cannot access.
