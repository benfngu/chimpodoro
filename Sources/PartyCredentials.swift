import Foundation
import Security

/// Party credentials are separate from local preferences and never included in logs.
enum PartyCredentials {
    struct Saved: Codable { let membership: PartyMembership; let endpoint: String }
    private static var query: [String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"local.ben.chimpodoro.party",kSecAttrAccount as String:"membership"] }
    static func load() -> Saved? {
        var query = self.query; query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Saved.self,from:data)
    }
    @discardableResult static func save(_ member: PartyMembership, endpoint: String) -> Bool {
        guard let data = try? JSONEncoder().encode(Saved(membership:member,endpoint:endpoint)) else {return false}
        let updates = [kSecValueData as String:data]
        var result = SecItemUpdate(query as CFDictionary,updates as CFDictionary)
        if result == errSecItemNotFound {
            var item = query;item[kSecValueData as String]=data
            item[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            result=SecItemAdd(item as CFDictionary,nil)
        }
        return result == errSecSuccess
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
