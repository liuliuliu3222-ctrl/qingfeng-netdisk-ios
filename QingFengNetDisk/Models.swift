import Foundation

// MARK: - 容错 JSON 读取（对应原 APK 中 optInt / optLong / optString 的宽容语义）

extension Dictionary where Key == String, Value == Any {

    func intOpt(_ key: String) -> Int? {
        switch self[key] {
        case let number as NSNumber: return number.intValue
        case let text as String: return Int(text)
        default: return nil
        }
    }

    func int64Opt(_ key: String) -> Int64? {
        switch self[key] {
        case let number as NSNumber: return number.int64Value
        case let text as String: return Int64(text)
        default: return nil
        }
    }

    func stringOpt(_ key: String) -> String? {
        switch self[key] {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    func boolOpt(_ key: String) -> Bool? {
        switch self[key] {
        case let number as NSNumber: return number.boolValue
        case let text as String: return text == "1" || text.lowercased() == "true"
        default: return nil
        }
    }

    func objectsOpt(_ key: String) -> [[String: Any]] {
        guard let list = self[key] as? [Any] else { return [] }
        return list.compactMap { $0 as? [String: Any] }
    }
}

// MARK: - 文件条目

struct QFFile: Identifiable, Hashable {
    let id: Int
    var name: String
    var isFolder: Bool
    var size: Int64
    var mime: String
    var hasThumb: Bool
    var trashedAt: String?

    init(id: Int,
         name: String,
         isFolder: Bool,
         size: Int64,
         mime: String,
         hasThumb: Bool = false,
         trashedAt: String? = nil) {
        self.id = id
        self.name = name
        self.isFolder = isFolder
        self.size = size
        self.mime = mime
        self.hasThumb = hasThumb
        self.trashedAt = trashedAt
    }

    init?(json: [String: Any]) {
        guard let id = json.intOpt("id"), let name = json.stringOpt("name") else { return nil }
        self.id = id
        self.name = name
        self.isFolder = (json.intOpt("is_folder") ?? 0) == 1
        self.size = json.int64Opt("size") ?? 0
        self.mime = json.stringOpt("mime") ?? ""
        self.hasThumb = json.boolOpt("has_thumb") ?? false
        self.trashedAt = json.stringOpt("trashed_at")
    }

    static func parseList(_ json: [String: Any]) -> [QFFile] {
        json.objectsOpt("items").compactMap { QFFile(json: $0) }
    }

    var kind: Kind {
        if isFolder { return .folder }
        let lower = name.lowercased()
        let type = mime.lowercased()
        if type.hasPrefix("image") { return .image }
        if type.hasPrefix("video") { return .video }
        if type.hasPrefix("audio") { return .audio }
        if type.hasPrefix("text") { return .text }
        if lower.hasSuffix(".pdf") { return .pdf }
        if lower.hasSuffix(".zip") || lower.hasSuffix(".rar") || lower.hasSuffix(".7z") { return .archive }
        if lower.hasSuffix(".doc") || lower.hasSuffix(".docx") { return .document }
        if lower.hasSuffix(".xls") || lower.hasSuffix(".xlsx") || lower.hasSuffix(".csv") { return .sheet }
        if lower.hasSuffix(".txt") || lower.hasSuffix(".md") || lower.hasSuffix(".json")
            || lower.hasSuffix(".xml") || lower.hasSuffix(".log") || lower.hasSuffix(".js")
            || lower.hasSuffix(".java") || lower.hasSuffix(".py") { return .text }
        return .other
    }

    var canPreviewInline: Bool {
        switch kind {
        case .image, .video, .audio: return true
        case .text: return size <= 2 * 1024 * 1024
        default: return false
        }
    }

    var displayNameForTrash: String {
        guard let trashedAt = trashedAt else { return name }
        let cleaned = trashedAt.replacingOccurrences(of: "T", with: " ")
        return "\(name) · 删除于 \(cleaned)"
    }

    enum Kind {
        case folder, image, video, audio, text, pdf, archive, document, sheet, other

        var symbol: String {
            switch self {
            case .folder: return "folder.fill"
            case .image: return "photo"
            case .video: return "play.rectangle"
            case .audio: return "waveform"
            case .text: return "doc.plaintext"
            case .pdf: return "doc.richtext"
            case .archive: return "doc.zipper"
            case .document: return "doc.text"
            case .sheet: return "tablecells"
            case .other: return "doc"
            }
        }
    }
}

// MARK: - 会员等级

struct QFTier: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var quotaBytes: Int64
}

// MARK: - 当前用户

struct QFMe: Equatable {
    var username: String = ""
    var quotaBytes: Int64 = 0
    var usedBytes: Int64 = 0
    var tierName: String = "普通会员"
    var isAdmin: Bool = false
    var tiers: [QFTier] = []

    init() {}

    init(json: [String: Any]) {
        username = json.stringOpt("username") ?? ""
        quotaBytes = json.int64Opt("quota_bytes") ?? 0
        usedBytes = json.int64Opt("used_bytes") ?? 0
        tierName = json.stringOpt("tier_name") ?? "普通会员"
        isAdmin = (json.intOpt("is_admin") ?? 0) == 1
        tiers = json.objectsOpt("tiers").map {
            QFTier(name: $0.stringOpt("name") ?? "", quotaBytes: $0.int64Opt("quota_bytes") ?? 0)
        }
    }

    var percent: Int {
        guard quotaBytes > 0 else { return 0 }
        return Int(usedBytes * 100 / quotaBytes)
    }

    var fraction: Double {
        guard quotaBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(quotaBytes)))
    }
}

// MARK: - 管理员视角的用户

struct QFAdminUser: Identifiable, Hashable {
    var id: String { username }
    var username: String
    var tierName: String
    var usedBytes: Int64
    var quotaBytes: Int64
}

// MARK: - 传输任务

struct TransferTask: Identifiable, Hashable {
    enum Kind: Int {
        case upload = 0
        case download = 1

        var title: String { self == .upload ? "上传" : "下载" }
        var symbol: String { self == .upload ? "arrow.up.circle" : "arrow.down.circle" }
    }

    enum State: Int {
        case running = 0
        case done = 1
        case failed = 2
    }

    let id = UUID()
    let kind: Kind
    var name: String
    var total: Int64
    var done: Int64 = 0
    var state: State = .running
    var message: String = ""

    var percent: Int {
        guard total > 0 else { return state == .done ? 100 : 0 }
        return min(100, Int(done * 100 / total))
    }

    var statusText: String {
        switch state {
        case .done:
            return "已完成 · \(ByteText.string(total))"
        case .failed:
            return "失败：\(message.isEmpty ? "未知错误" : message)"
        case .running:
            return "进行中 \(percent)% · \(ByteText.string(done)) / \(ByteText.string(total))"
        }
    }
}

// MARK: - 字节格式化（对应 Utils.fmtSize）

enum ByteText {
    static func string(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }
}
