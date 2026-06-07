# 🌸 Melati

Private daily journaling. Web + macOS, sharing one TipTap editor.

## Web (`/`, `src/`)

React 19 · Vite · TipTap · IndexedDB (`idb-keyval`) · Tailwind v4 · Biome.

```sh
pnpm i
pnpm dev          # vite
pnpm build        # tsc -b && vite build
pnpm check        # biome
```

## Mac (`mac/`)

Native SwiftUI app. SQLCipher-encrypted entries with the key in Keychain. The TipTap editor is bundled as a single-file HTML page (`mac/editor-embed`) and hosted in a `WKWebView`.

Requires macOS 14+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.

```sh
cd mac/editor-embed && npm i && npm run build   # build embedded editor
cd .. && xcodegen                                # regenerate Melati.xcodeproj
open Melati.xcodeproj                            # build & run
```

Shortcuts: ⌘N new entry · ⌘1/⌘2/⌘3 today/entries/calendar · ←/→ flip entries · ⌘[ back · ⌘? help.

## Privacy

No network, no analytics, no accounts. Mac entries are SQLCipher-encrypted on disk; web entries live only in your browser's IndexedDB.
