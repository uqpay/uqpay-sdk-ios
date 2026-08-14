//
//  KeychainHelper.swift
//  UqpayCore
//
//  Created by UQPAY on 09/10/2025.
//

import Foundation
import Security

/// Helper class for securely storing and retrieving data from Keychain
public final class KeychainHelper {

    // MARK: - Singleton
    public static let shared = KeychainHelper()

    private init() {}

    // MARK: - Public Methods

    /// Save a string value to Keychain
    /// - Parameters:
    ///   - value: The string value to save
    ///   - key: The key to identify the value
    /// - Returns: True if save was successful, false otherwise
    @discardableResult
    public func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }
        return save(data, forKey: key)
    }

    /// Save data to Keychain
    /// - Parameters:
    ///   - data: The data to save
    ///   - key: The key to identify the data
    /// - Returns: True if save was successful, false otherwise
    @discardableResult
    public func save(_ data: Data, forKey key: String) -> Bool {
        // Delete any existing item
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // ThisDeviceOnly: the stored payment context carries a client
            // secret that is only meaningful on the device mid-payment —
            // it must not ride an encrypted backup onto another device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve a string value from Keychain
    /// - Parameter key: The key to identify the value
    /// - Returns: The string value if found, nil otherwise
    public func retrieve(forKey key: String) -> String? {
        guard let data = retrieveData(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieve data from Keychain
    /// - Parameter key: The key to identify the data
    /// - Returns: The data if found, nil otherwise
    public func retrieveData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    /// Delete a value from Keychain
    /// - Parameter key: The key to identify the value
    /// - Returns: True if delete was successful, false otherwise
    @discardableResult
    public func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Save a Codable object to Keychain as JSON
    /// - Parameters:
    ///   - object: The Codable object to save
    ///   - key: The key to identify the object
    /// - Returns: True if save was successful, false otherwise
    @discardableResult
    public func saveObject<T: Codable>(_ object: T, forKey key: String) -> Bool {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(object)
            return save(data, forKey: key)
        } catch {
            // Log the failure, never the object being stored.
            UqpayLogger.shared.error("Failed to encode object for keychain key '\(key)': \(error.localizedDescription)")
            return false
        }
    }

    /// Retrieve a Codable object from Keychain
    /// - Parameters:
    ///   - type: The type of the object to retrieve
    ///   - key: The key to identify the object
    /// - Returns: The decoded object if found, nil otherwise
    public func retrieveObject<T: Codable>(ofType type: T.Type, forKey key: String) -> T? {
        guard let data = retrieveData(forKey: key) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch {
            // Log the failure, never the stored data.
            UqpayLogger.shared.error("Failed to decode object for keychain key '\(key)': \(error.localizedDescription)")
            return nil
        }
    }
}
