//
//  KeychainSecretStore.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation
import Security

nonisolated struct KeychainSecretReference: Codable, Hashable, Sendable {
    var service: String
    var account: String

    var rawValue: String {
        "\(service):\(account)"
    }
}

nonisolated struct KeychainSecretStore: Sendable {
    static let defaultService = "flannel.ai.keys"

    func save(_ secret: String, account: String, service: String = defaultService) throws -> KeychainSecretReference {
        let data = Data(secret.utf8)
        let reference = KeychainSecretReference(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return reference
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainSecretError(status: updateStatus)
        }

        var insertQuery = query
        insertQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainSecretError(status: addStatus)
        }

        return reference
    }

    func read(_ reference: KeychainSecretReference) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.service,
            kSecAttrAccount as String: reference.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw KeychainSecretError(status: status)
        }

        return secret
    }

    func delete(_ reference: KeychainSecretReference) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.service,
            kSecAttrAccount as String: reference.account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretError(status: status)
        }
    }
}

nonisolated struct KeychainSecretError: LocalizedError, Sendable {
    var status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}
