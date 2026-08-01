#!/usr/bin/env swift
//
// Migrate existing Melati data -> Noot (app renamed back to Noot, 2026-07).
//
// Run once, OUTSIDE both apps:
//   swift mac/scripts/migrate-from-melati.swift
//
// Does:
//   1. Reads 32-byte DB key from Keychain service "com.lennertjansen.melati".
//   2. Writes it to "com.lennertjansen.noot".
//   3. Copies journal.db from old container path to new container path.
//
// Idempotent: re-running checks for an existing new-service Keychain entry
// and skips the write if found; copies DB only if new-side doesn't exist.
//
// Pass --force to overwrite both (e.g. when Noot's first launch
// auto-generated a fresh empty Keychain entry + DB before migration ran).
//
// Why a script and not in-app: ad-hoc-signed apps have distinct code
// signatures, so the new app cannot read the old app's Keychain entries
// via in-app SecItem APIs. Running outside the app prompts macOS to
// authorize Keychain access via user prompt.

import Foundation
import Security

let FORCE = CommandLine.arguments.contains("--force")

let OLD_SERVICE = "com.lennertjansen.melati"
let NEW_SERVICE = "com.lennertjansen.noot"
let ACCOUNT = "primary-database-key"

let home = FileManager.default.homeDirectoryForCurrentUser
let oldDB = home
    .appendingPathComponent("Library/Containers/\(OLD_SERVICE)/Data/Library/Application Support/journal.db")
let newDir = home
    .appendingPathComponent("Library/Containers/\(NEW_SERVICE)/Data/Library/Application Support")
let newDB = newDir.appendingPathComponent("journal.db")

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

// 3. Copy DB
let fm = FileManager.default
guard fm.fileExists(atPath: oldDB.path) else {
    fail("old DB not found at \(oldDB.path)")
}

if fm.fileExists(atPath: newDB.path) {
    if FORCE {
        log("--force: removing existing \(newDB.path)")
        try? fm.removeItem(at: newDB)
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
    ok("copied DB")
}

print("\nmigration complete - launch Noot.app")
