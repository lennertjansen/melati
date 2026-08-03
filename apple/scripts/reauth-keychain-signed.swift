#!/usr/bin/env swift
//
// Re-authorize the Noot DB key for the team-signed build (2026-08).
//
// Why: the diary key was created by the ad-hoc-signed Noot. After switching to
// team signing (6VG5LWYXK5) the new binary has a different code signature and
// cannot silently read the old Keychain item. Rewriting the item outside the
// app (this script) resets its ownership; the signed app then triggers a
// one-time macOS prompt - click "Always Allow".
//
// Run once, with Noot NOT running, BEFORE launching the signed build:
//   swift mac/scripts/reauth-keychain-signed.swift
//
// Does NOT touch journal.db. Aborts if the key looks wrong. Idempotent.

import Foundation
import Security

let SERVICE = "com.lennertjansen.noot"
let ACCOUNT = "primary-database-key"

func log(_ s: String) { print("→ \(s)") }
func ok(_ s: String) { print("✓ \(s)") }
func fail(_ s: String) -> Never { fputs("✗ \(s)\n", stderr); exit(1) }

// 1. Read existing key (macOS may prompt to allow keychain access - approve it)
log("reading key from Keychain (\(SERVICE)) - approve the prompt if one appears")
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: SERVICE,
    kSecAttrAccount as String: ACCOUNT,
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne,
]
var result: AnyObject?
let readStatus = SecItemCopyMatching(query as CFDictionary, &result)
guard readStatus == errSecSuccess, let key = result as? Data else {
    fail("keychain read failed: OSStatus \(readStatus) - nothing was changed")
}
guard key.count == 32 else {
    fail("expected 32-byte key, got \(key.count) bytes - aborting, nothing was changed")
}
ok("read \(key.count)-byte key")

// 2. Delete + rewrite so ownership resets
log("rewriting item")
let deleteQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: SERVICE,
    kSecAttrAccount as String: ACCOUNT,
]
let delStatus = SecItemDelete(deleteQuery as CFDictionary)
guard delStatus == errSecSuccess else {
    fail("delete failed: OSStatus \(delStatus)")
}
let attrs: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: SERVICE,
    kSecAttrAccount as String: ACCOUNT,
    kSecValueData as String: key,
    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
]
let addStatus = SecItemAdd(attrs as CFDictionary, nil)
guard addStatus == errSecSuccess else {
    fail("""
    rewrite failed: OSStatus \(addStatus). YOUR KEY IS PRINTED BELOW - store it \
    somewhere safe and re-add it manually via Keychain Access if needed:
    \(key.map { String(format: "%02x", $0) }.joined())
    """)
}
ok("item rewritten")

print("\ndone - launch the signed Noot.app and click \"Always Allow\" when prompted")
