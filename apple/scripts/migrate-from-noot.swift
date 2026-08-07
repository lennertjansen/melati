#!/usr/bin/env swift
//
// Migrate existing Noot data -> Melati (app renamed back to Melati, 2026-08).
// Reverse of the old migrate-from-melati.swift (removed with this rename).
//
// Run once, OUTSIDE both apps:
//   swift apple/scripts/migrate-from-noot.swift
//
// Does:
//   1. Reads 32-byte DB key from Keychain service "com.lennertjansen.noot".
//   2. Writes it to "com.lennertjansen.melati".
//   3. Copies journal.db (+ -wal/-shm sidecars if present) from the old
//      container path to the new container path.
//
// NEVER touches the old (noot) side: reads only. Idempotent: re-running
// skips the Keychain write if the new entry exists and the DB copy if the
// new-side DB exists.
//
// Pass --force to overwrite both new-side artifacts (e.g. when Melati's
// first launch auto-generated a fresh empty Keychain entry + DB before
// migration ran).
//
// AFTER migrating: the copied DB still carries sync state tied to the old
// noot iCloud container. First Melati launch must be a Debug build with
//   -melati.resetSyncState YES
// so every entry re-uploads into the melati container.
//
// Why a script and not in-app: the apps have distinct code signatures, so
// the new app cannot read the old app's Keychain entries via in-app
// SecItem APIs. Running outside the app prompts macOS to authorize
// Keychain access via user prompt.
//
// Test seams (E2E testing WITHOUT touching real data): the services and
// paths can be overridden via env vars MIGRATE_OLD_SERVICE,
// MIGRATE_NEW_SERVICE, MIGRATE_OLD_DB, MIGRATE_NEW_DIR. Any override
// prints a loud TEST MODE banner. Never set these for a real migration.

import Foundation
import Security

let FORCE = CommandLine.arguments.contains("--force")
let env = ProcessInfo.processInfo.environment

let OLD_SERVICE = env["MIGRATE_OLD_SERVICE"] ?? "com.lennertjansen.noot"
let NEW_SERVICE = env["MIGRATE_NEW_SERVICE"] ?? "com.lennertjansen.melati"
let ACCOUNT = "primary-database-key"

let home = FileManager.default.homeDirectoryForCurrentUser
let oldDB = env["MIGRATE_OLD_DB"].map { URL(fileURLWithPath: $0) } ?? home
    .appendingPathComponent("Library/Containers/com.lennertjansen.noot/Data/Library/Application Support/journal.db")
let newDir = env["MIGRATE_NEW_DIR"].map { URL(fileURLWithPath: $0) } ?? home
    .appendingPathComponent("Library/Containers/com.lennertjansen.melati/Data/Library/Application Support")
let newDB = newDir.appendingPathComponent("journal.db")

if ["MIGRATE_OLD_SERVICE", "MIGRATE_NEW_SERVICE", "MIGRATE_OLD_DB", "MIGRATE_NEW_DIR"].contains(where: { env[$0] != nil }) {
    print("!!! TEST MODE - overrides active, not migrating the real containers !!!")
}

func log(_ s: String) { print("→ \(s)") }
func ok(_ s: String) { print("✓ \(s)") }
func fail(_ s: String) -> Never { fputs("✗ \(s)\n", stderr); exit(1) }

func readKey(service: String) -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: ACCOUNT,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
        fail("keychain read failed (\(service)): OSStatus \(status)")
    }
    return data
}

func writeKey(service: String, key: Data) {
    let attrs: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: ACCOUNT,
        kSecValueData as String: key,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemAdd(attrs as CFDictionary, nil)
    guard status == errSecSuccess else {
        fail("keychain write failed (\(service)): OSStatus \(status)")
    }
}

func deleteKey(service: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: ACCOUNT,
    ]
    SecItemDelete(query as CFDictionary)
}

// 1. Read old key
log("reading key from Keychain (\(OLD_SERVICE))")
guard let key = readKey(service: OLD_SERVICE) else {
    fail("no key found at \(OLD_SERVICE) / \(ACCOUNT) - nothing to migrate")
}
guard key.count == 32 else {
    fail("expected 32-byte key, got \(key.count) bytes")
}
ok("read \(key.count) bytes")

// 2. Write to new service
if readKey(service: NEW_SERVICE) != nil {
    if FORCE {
        log("--force: deleting existing \(NEW_SERVICE) entry")
        deleteKey(service: NEW_SERVICE)
        writeKey(service: NEW_SERVICE, key: key)
        ok("overwrote key")
    } else {
        ok("Keychain entry for \(NEW_SERVICE) already exists - skipping (pass --force to overwrite)")
    }
} else {
    log("writing key to Keychain (\(NEW_SERVICE))")
    writeKey(service: NEW_SERVICE, key: key)
    ok("wrote key")
}

// 3. Copy DB (+ WAL sidecars: present when the old app didn't checkpoint
// on last close; skipping them would silently drop the newest writes)
let fm = FileManager.default
guard fm.fileExists(atPath: oldDB.path) else {
    fail("old DB not found at \(oldDB.path)")
}

let sidecars = ["-wal", "-shm"]

if fm.fileExists(atPath: newDB.path) {
    if FORCE {
        log("--force: removing existing \(newDB.path) (+ sidecars)")
        try? fm.removeItem(at: newDB)
        for ext in sidecars {
            try? fm.removeItem(at: URL(fileURLWithPath: newDB.path + ext))
        }
    } else {
        ok("new DB already exists - skipping copy (pass --force to overwrite)")
    }
}

if !fm.fileExists(atPath: newDB.path) {
    log("creating \(newDir.path)")
    try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
    log("copying DB → \(newDB.path)")
    do {
        try fm.copyItem(at: oldDB, to: newDB)
    } catch {
        fail("copy failed: \(error)")
    }
    for ext in sidecars {
        let src = URL(fileURLWithPath: oldDB.path + ext)
        if fm.fileExists(atPath: src.path) {
            do {
                try fm.copyItem(at: src, to: URL(fileURLWithPath: newDB.path + ext))
                ok("copied sidecar \(src.lastPathComponent)")
            } catch {
                fail("sidecar copy failed: \(error)")
            }
        }
    }
    ok("copied DB")
}

print("""

migration complete. Next:
  launch Melati (Debug) once with: -melati.resetSyncState YES
  (forgets old-container sync state, re-uploads full history)
""")
