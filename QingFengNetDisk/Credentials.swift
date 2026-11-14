import Foundation
import Security

// MARK: - Keychain：iOS 上用来替代 Android 明文 SharedPreferences 保存 token

enum KeychainStore {
    private static let service = "com.qingfeng.netdisk.ios"

    static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 应用设置（对应 APK 的 com.qingfeng.netdisk.Prefs）

enum AppSettings {
    /// 界面展示用版本号：直接读 Info.plist，避免多处硬编码不同步
    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }

    /// 原 APK 内置的默认服务器，可在设置页修改
    static let defaultServer = "https://a131653141fe81eec.app.workbuddy.host"
    /// 原 APK 内置的默认分享码
    static let defaultSharecode = "AOMNHSOF2D"

    private static let store = UserDefaults.standard
    private static let tokenAccount = "auth.token"
    private static let passwordPrefix = "saved.pass."

    // MARK: 多账号（已保存的账号）

    /// 本机记住的账号列表，最近使用的在前
    static var savedAccounts: [String] {
        get { store.stringArray(forKey: "savedAccounts") ?? [] }
        set { store.set(newValue, forKey: "savedAccounts") }
    }

    /// 当前活跃账号（切换 / 删除时以用户名为准）
    static var currentUsername: String {
        get { store.string(forKey: "username") ?? "" }
    }

    /// 账号密码保存在 Keychain（account = saved.pass.<用户名>）
    static func storedPassword(for username: String) -> String {
        guard !username.isEmpty else { return "" }
        return KeychainStore.read(account: passwordPrefix + username)
    }

    static func setStoredPassword(_ password: String, for username: String) {
        guard !username.isEmpty else { return }
        if password.isEmpty {
            KeychainStore.delete(account: passwordPrefix + username)
        } else {
            KeychainStore.save(password, account: passwordPrefix + username)
        }
    }

    /// 登录成功后调用：把账号放进已保存列表（最近使用优先）
    static func rememberAccount(username: String, password: String) {
        guard !username.isEmpty else { return }
        if !password.isEmpty {
            setStoredPassword(password, for: username)
        }
        var list = savedAccounts.filter { $0 != username }
        list.insert(username, at: 0)
        savedAccounts = list
    }

    /// 从已保存列表移除账号（同时删除本机密码）
    static func forgetAccount(_ username: String) {
        setStoredPassword("", for: username)
        savedAccounts = savedAccounts.filter { $0 != username }
    }

    static var hasSavedAccounts: Bool { !savedAccounts.isEmpty }

    /// 该账号是否在本机保存了密码
    static func hasPasswordSaved(for username: String) -> Bool {
        !storedPassword(for: username).isEmpty
    }

    static var server: String {
        get {
            let value = store.string(forKey: "server") ?? defaultServer
            return value.isEmpty ? defaultServer : value
        }
        set {
            var value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            while value.hasSuffix("/") { value.removeLast() }
            store.set(value, forKey: "server")
        }
    }

    static var sharecode: String {
        get { store.string(forKey: "sharecode") ?? defaultSharecode }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "sharecode") }
    }

    static var chunkSizeMB: Int {
        get { store.integer(forKey: "chunkSizeMB") == 0 ? 5 : store.integer(forKey: "chunkSizeMB") }
        set { store.set(newValue, forKey: "chunkSizeMB") }
    }

    static var username: String {
        get { store.string(forKey: "username") ?? "" }
        set { store.set(newValue, forKey: "username") }
    }

    static var token: String {
        get { KeychainStore.read(account: tokenAccount) }
        set {
            if newValue.isEmpty {
                KeychainStore.delete(account: tokenAccount)
            } else {
                KeychainStore.save(newValue, account: tokenAccount)
            }
        }
    }

    static var isLoggedIn: Bool { !token.isEmpty }

    // /api/me 的本地缓存，用于断网时首页仍有内容可显示
    static var cachedTier: String {
        get { store.string(forKey: "tier") ?? "普通会员" }
        set { store.set(newValue, forKey: "tier") }
    }

    static var cachedQuota: Int64 {
        get { (store.object(forKey: "quota") as? NSNumber)?.int64Value ?? 0 }
        set { store.set(NSNumber(value: newValue), forKey: "quota") }
    }

    static var cachedUsed: Int64 {
        get { (store.object(forKey: "used") as? NSNumber)?.int64Value ?? 0 }
        set { store.set(NSNumber(value: newValue), forKey: "used") }
    }

    static func cache(_ me: QFMe) {
        username = me.username.isEmpty ? username : me.username
        cachedTier = me.tierName
        cachedQuota = me.quotaBytes
        cachedUsed = me.usedBytes
    }

    static var cachedMe: QFMe {
        var me = QFMe()
        me.username = username
        me.tierName = cachedTier
        me.quotaBytes = cachedQuota
        me.usedBytes = cachedUsed
        return me
    }

    static func clearAuth() {
        token = ""
        store.removeObject(forKey: "username")
        store.removeObject(forKey: "quota")
        store.removeObject(forKey: "used")
        store.removeObject(forKey: "tier")
    }
}
