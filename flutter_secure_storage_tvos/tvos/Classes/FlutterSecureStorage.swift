import Foundation

class FlutterSecureStorage {
    private func parseAccessibleAttr(accessibility: String?) -> CFString {
        guard let accessibility = accessibility else {
            return kSecAttrAccessibleWhenUnlocked
        }
        
        switch accessibility {
        case "passcode":
            return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        case "unlocked":
            return kSecAttrAccessibleWhenUnlocked
        case "unlocked_this_device":
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case "first_unlock":
            return kSecAttrAccessibleAfterFirstUnlock
        case "first_unlock_this_device":
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        default:
            return kSecAttrAccessibleWhenUnlocked
        }
    }

    private func baseQuery(key: String?, groupId: String?, accountName: String?, synchronizable: Bool?, accessibility: String?, returnData: Bool?) -> [CFString: Any] {
        var keychainQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccessible: parseAccessibleAttr(accessibility: accessibility),
        ]
        if #available(iOS 10.15, macOS 10.15, tvOS 10.15, *) {
            keychainQuery[kSecUseDataProtectionKeychain] = true
        }
        
        if let key = key {
            keychainQuery[kSecAttrAccount] = key
        }
        
        if let groupId = groupId {
            keychainQuery[kSecAttrAccessGroup] = groupId
        }
        
        if let accountName = accountName {
            keychainQuery[kSecAttrService] = accountName
        }
        
        if let synchronizable = synchronizable {
            keychainQuery[kSecAttrSynchronizable] = synchronizable
        }
        
        if let returnData = returnData {
            keychainQuery[kSecReturnData] = returnData
        }
        return keychainQuery
    }
    
    internal func containsKey(key: String, groupId: String?, accountName: String?, synchronizable: Bool?, accessibility: String?) -> Result<Bool, OSSecError> {  
        let keychainQuery = baseQuery(key: key, groupId: groupId, accountName: accountName, synchronizable: synchronizable, accessibility: accessibility, returnData: false)
        
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return .success(true)
        case errSecItemNotFound:
            return .success(false)
        default:
            return .failure(OSSecError(status: status))
        }
    }
    
    internal func readAll(groupId: String?, accountName: String?, synchronizable: Bool?, accessibility: String?) -> FlutterSecureStorageResponse {
        var keychainQuery = baseQuery(key: nil, groupId: groupId, accountName: accountName, synchronizable: synchronizable, accessibility: accessibility, returnData: true)
        
        keychainQuery[kSecMatchLimit] = kSecMatchLimitAll
        keychainQuery[kSecReturnAttributes] = true
        
        var ref: AnyObject?
        let status = SecItemCopyMatching(
            keychainQuery as CFDictionary,
            &ref
        )
        
        if status == errSecItemNotFound {
            // readAll() returns all elements, so return nil if the items does not exist
            return FlutterSecureStorageResponse(status: errSecSuccess, value: nil)
        }
        
        var results: [String: String] = [:]
        
        if status == noErr, let items = ref as? [[String: Any]] {
            for item in items {
                if let key = item[kSecAttrAccount as String] as? String,
                   let data = item[kSecValueData as String] as? Data,
                   let value = String(data: data, encoding: .utf8) {
                    results[key] = value
                }
            }
        }
        
        return FlutterSecureStorageResponse(status: status, value: results)
    }
    
    internal func read(key: String, groupId: String?, accountName: String?, synchronizable: Bool?, accessibility: String?) -> FlutterSecureStorageResponse {
        let keychainQuery = baseQuery(key: key, groupId: groupId, accountName: accountName, synchronizable: synchronizable, accessibility: accessibility, returnData: true)
        
        var ref: AnyObject?
        let status = SecItemCopyMatching(
            keychainQuery as CFDictionary,
            &ref
        )
        
        // Return nil if the key is not found
        if status == errSecItemNotFound {
            return FlutterSecureStorageResponse(status: errSecSuccess, value: nil)
        }
        
        var value: String? = nil
        
        if status == noErr, let data = ref as? Data {
            value = String(data: data, encoding: .utf8)
        }

        return FlutterSecureStorageResponse(status: status, value: value)
    }
    
    internal func deleteAll(groupId: String?, accountName: String?, synchronizable: Bool?, accessibility: String?) -> FlutterSecureStorageResponse {
        let keychainQuery = baseQuery(key: nil, groupId: groupId, accountName: accountName, synchronizable: synchronizable, accessibility: accessibility, returnData: nil)
        let status = SecItemDelete(keychainQuery as CFDictionary)
        
        if status == errSecItemNotFound {
            // deleteAll() deletes all items, so return nil if the items does not exist
            return FlutterSecureStorageResponse(status: errSecSuccess, value: nil)
        }

        return FlutterSecureStorageResponse(status: status, value: nil)
    }
    
    internal func delete(key: String, groupId: String?, accountName: String?, synchronizable: Bool?, accessibility: String?) -> FlutterSecureStorageResponse {
        let keychainQuery = baseQuery(key: key, groupId: groupId, accountName: accountName, synchronizable: synchronizable, accessibility: accessibility, returnData: true)
        let status = SecItemDelete(keychainQuery as CFDictionary)
        
        // Return nil if the key is not found
        if status == errSecItemNotFound {
            return FlutterSecureStorageResponse(status: errSecSuccess, value: nil)
        }
        
        return FlutterSecureStorageResponse(status: status, value: nil)
    }
    
    internal func write(key: String, value: String, groupId: String?, accountName: String?, synchronizable: Bool?, accessibility: String?) -> FlutterSecureStorageResponse {        
        var keyExists: Bool = false

    	switch containsKey(key: key, groupId: groupId, accountName: accountName, synchronizable: synchronizable, accessibility: accessibility) {
        case .success(let exists):
            keyExists = exists
            break;
        case .failure(let err):
            return FlutterSecureStorageResponse(status: err.status, value: nil)
        }

        let attrAccessible = parseAccessibleAttr(accessibility: accessibility)
        var keychainQuery = baseQuery(key: key, groupId: groupId, accountName: accountName, synchronizable: synchronizable, accessibility: accessibility, returnData: nil)

        if keyExists {
            var update: [CFString: Any?] = [
                kSecValueData: value.data(using: .utf8),
                kSecAttrAccessible: attrAccessible,
                kSecAttrSynchronizable: synchronizable
            ]
            if #available(iOS 10.15, macOS 10.15, tvOS 10.15, *) {
                update[kSecUseDataProtectionKeychain] = true
            }

            let status = SecItemUpdate(keychainQuery as CFDictionary, update as CFDictionary)
            
            return FlutterSecureStorageResponse(status: status, value: nil)
        } else {
            keychainQuery[kSecValueData] = value.data(using: .utf8)
            keychainQuery[kSecAttrAccessible] = attrAccessible
            if #available(iOS 10.15, macOS 10.15, tvOS 10.15, *) {
                keychainQuery[kSecUseDataProtectionKeychain] = true
            }
            
            let status = SecItemAdd(keychainQuery as CFDictionary, nil)

            return FlutterSecureStorageResponse(status: status, value: nil)
        }
    }    
}

struct FlutterSecureStorageResponse {
    var status: OSStatus?
    var value: Any?
}

struct OSSecError: Error {
    var status: OSStatus
}
