import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 清风网盘 HTTP 客户端。
/// 协议完全对齐原 Android 实现：
/// - 认证头同时携带 `X-QF-Token` 与 `Authorization: Bearer <token>`
/// - 每个业务请求自动追加 `sharecode` 查询参数
/// - 错误体为 `{"error": "..."}`
final class ApiClient {

    static let shared = ApiClient()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 300
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    // MARK: - URL 构造

    /// RFC 3986 unreserved 集合，避免 `+` 被服务端解析成空格
    static func encode(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    private func url(path: String) throws -> URL {
        var full = path
        let sharecode = AppSettings.sharecode
        if !sharecode.isEmpty {
            full += full.contains("?") ? "&" : "?"
            full += "sharecode=" + ApiClient.encode(sharecode)
        }
        guard let url = URL(string: AppSettings.server + full) else {
            throw APIError(message: "服务器地址无效，请到设置页检查")
        }
        return url
    }

    private func makeRequest(_ method: String,
                             path: String,
                             body: Data? = nil,
                             contentType: String? = nil,
                             auth: Bool = true) throws -> URLRequest {
        var request = URLRequest(url: try url(path: path))
        request.httpMethod = method
        if auth {
            let token = AppSettings.token
            request.setValue(token, forHTTPHeaderField: "X-QF-Token")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let body = body {
            request.httpBody = body
        }
        return request
    }

    // MARK: - 底层收发

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        // SwiftUI `.refreshable` 的 Task 会在下拉手势结束 / 视图重绘时被系统取消。
        // 若让请求继承这个 Task，URLSession 会抛 URLError.cancelled（中文系统显示
        // 「已取消」），上层就会把列表清空并弹出错误提示 —— 刷新等于白刷。
        // 这里用不继承取消状态的 detached Task 承载请求：即使调用方 Task 被取消，
        // 请求仍会真正发出并拿到服务端最新数据（上传新文件后刷新一定有效）。
        let task = Task.detached(priority: .userInitiated) { [session] in
            try await session.data(for: request)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await task.value
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                throw APIError(message: "请求已取消")
            }
            throw APIError(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "网络异常")
        }
        if http.statusCode >= 400 {
            throw APIError(message: ApiClient.errorMessage(data: data, status: http.statusCode))
        }
        return data
    }

    static func errorMessage(data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String,
           !message.isEmpty {
            return message
        }
        return "请求失败 (\(status))"
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError(message: "响应解析失败")
        }
        return object
    }

    private func postJSON(_ path: String, _ payload: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest("POST",
                                      path: path,
                                      body: body,
                                      contentType: "application/json; charset=utf-8")
        _ = try await send(request)
    }

    private func postJSONObject(_ path: String, _ payload: [String: Any]) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest("POST",
                                      path: path,
                                      body: body,
                                      contentType: "application/json; charset=utf-8")
        return try jsonObject(try await send(request))
    }

    // MARK: - 认证

    func auth(username: String, password: String, register: Bool) async throws -> String {
        let payload: [String: Any] = ["username": username, "password": password]
        let object = try await postJSONObject(register ? "/api/auth/register" : "/api/auth/login", payload)
        guard let token = object.stringOpt("token"), !token.isEmpty else {
            throw APIError(message: "登录响应缺少 token")
        }
        return token
    }

    func me() async throws -> QFMe {
        let request = try makeRequest("GET", path: "/api/me")
        let object = try jsonObject(try await send(request))
        return QFMe(json: object)
    }

    // MARK: - 文件

    func list(parentId: Int?) async throws -> [QFFile] {
        let value = parentId.map(String.init) ?? ""
        let request = try makeRequest("GET", path: "/api/files/list?parentId=\(value)")
        let object = try jsonObject(try await send(request))
        return QFFile.parseList(object)
    }

    func search(_ keyword: String) async throws -> [QFFile] {
        let request = try makeRequest("GET", path: "/api/search?q=" + ApiClient.encode(keyword))
        let object = try jsonObject(try await send(request))
        return QFFile.parseList(object)
    }

    func category(_ type: String) async throws -> [QFFile] {
        let request = try makeRequest("GET", path: "/api/files/category?type=" + ApiClient.encode(type))
        let object = try jsonObject(try await send(request))
        return QFFile.parseList(object)
    }

    func recent() async throws -> [QFFile] {
        let request = try makeRequest("GET", path: "/api/files/recent")
        let object = try jsonObject(try await send(request))
        return QFFile.parseList(object)
    }

    func mkdir(name: String, parentId: Int?) async throws {
        var payload: [String: Any] = ["name": name]
        if let parentId = parentId { payload["parentId"] = parentId }
        try await postJSON("/api/files/mkdir", payload)
    }

    func rename(id: Int, name: String) async throws {
        try await postJSON("/api/files/rename", ["id": id, "name": name])
    }

    func delete(id: Int) async throws {
        try await postJSON("/api/files/delete", ["ids": [id]])
    }

    // MARK: - 回收站

    func trashList() async throws -> [QFFile] {
        let request = try makeRequest("GET", path: "/api/trash/list")
        let object = try jsonObject(try await send(request))
        return QFFile.parseList(object)
    }

    func trashRestore(ids: [Int]) async throws {
        try await postJSON("/api/trash/restore", ["ids": ids])
    }

    func trashPurge(ids: [Int]) async throws {
        try await postJSON("/api/trash/purge", ["ids": ids])
    }

    func trashEmpty() async throws {
        try await postJSON("/api/trash/empty", [:])
    }

    // MARK: - 分享

    func shareCreate(id: Int, password: String?, expireHours: Int?) async throws -> String {
        var payload: [String: Any] = ["id": id]
        if let password = password, !password.isEmpty { payload["password"] = password }
        if let expireHours = expireHours { payload["expireHours"] = expireHours }
        let object = try await postJSONObject("/api/share/create", payload)
        return object.stringOpt("shareUrl") ?? ""
    }

    // MARK: - 管理员

    func adminUsers() async throws -> [QFAdminUser] {
        let request = try makeRequest("GET", path: "/api/admin/users")
        let object = try jsonObject(try await send(request))
        return object.objectsOpt("users").map {
            QFAdminUser(username: $0.stringOpt("username") ?? "",
                        tierName: $0.stringOpt("tier_name") ?? "",
                        usedBytes: $0.int64Opt("used_bytes") ?? 0,
                        quotaBytes: $0.int64Opt("quota_bytes") ?? 0)
        }
    }

    func adminSetQuota(username: String, quotaBytes: Int64) async throws {
        try await postJSON("/api/admin/set-quota",
                           ["username": username, "quota_bytes": quotaBytes])
    }

    // MARK: - 上传（5MB 分片，对齐 Uploader.CHUNK）

    static let chunkSize = 5 * 1024 * 1024

    func uploadInit(name: String, size: Int64, parentId: Int?, totalChunks: Int) async throws -> String {
        var payload: [String: Any] = [
            "name": name,
            "size": NSNumber(value: size),
            "totalChunks": totalChunks
        ]
        if let parentId = parentId { payload["parentId"] = parentId }
        let object = try await postJSONObject("/api/files/upload-init", payload)
        guard let uploadId = object.stringOpt("uploadId"), !uploadId.isEmpty else {
            throw APIError(message: "上传初始化响应异常")
        }
        return uploadId
    }

    func uploadChunk(uploadId: String, index: Int, data: Data) async throws {
        let path = "/api/files/chunk?uploadId=\(ApiClient.encode(uploadId))&index=\(index)"
        let request = try makeRequest("POST",
                                      path: path,
                                      body: data,
                                      contentType: "application/octet-stream")
        _ = try await send(request)
    }

    func uploadComplete(uploadId: String) async throws {
        try await postJSON("/api/files/upload-complete", ["uploadId": uploadId])
    }

    // MARK: - 下载与预览

    /// - onControl: 传出下载暂停控制器，参数 true=暂停(suspend)、false=恢复(resume)。
    ///   供传输页点任务本身实现「真实暂停」——直接挂起底层 URLSession 下载任务。
    func download(id: Int, to destination: URL, progress: ((Int64, Int64) -> Void)?,
                  onControl: ((@escaping (Bool) -> Void)) -> Void = { _ in }) async throws {
        let request = try makeRequest("GET", path: "/api/files/download/\(id)")
        let kit = DownloadKit(destination: destination, onProgress: progress)
        onControl { paused in
            if paused { kit.pause() } else { kit.resume() }
        }
        try await kit.start(request: request)
    }

    func fetchPreview(id: Int) async throws -> Data {
        let request = try makeRequest("GET", path: "/api/files/preview/\(id)")
        return try await send(request)
    }

    func fetchThumb(id: Int) async throws -> Data {
        let request = try makeRequest("GET", path: "/api/files/thumb/\(id)")
        return try await send(request)
    }

    /// 给 AVPlayer / WKWebView 等系统播放器使用的直链。
    /// 原 APK 在 sharecode 为空时会拼出 `.../thumb/1&token=` 的畸形 URL，
    /// 这里统一修正为合法的查询串。
    func streamingURL(id: Int, preview: Bool) -> URL? {
        var path = preview ? "/api/files/preview/\(id)" : "/api/files/download/\(id)"
        let sharecode = AppSettings.sharecode
        if sharecode.isEmpty {
            path += "?token=" + ApiClient.encode(AppSettings.token)
        } else {
            path += "?sharecode=" + ApiClient.encode(sharecode)
            path += "&token=" + ApiClient.encode(AppSettings.token)
        }
        return URL(string: AppSettings.server + path)
    }

    func thumbnailURL(id: Int) -> URL? {
        var path = "/api/files/thumb/\(id)"
        let sharecode = AppSettings.sharecode
        if sharecode.isEmpty {
            path += "?token=" + ApiClient.encode(AppSettings.token)
        } else {
            path += "?sharecode=" + ApiClient.encode(sharecode)
            path += "&token=" + ApiClient.encode(AppSettings.token)
        }
        return URL(string: AppSettings.server + path)
    }

    // MARK: - 连通性检测（设置页）

    static func checkHealth(server: String, sharecode: String) async -> (ok: Bool, message: String) {
        var base = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty, base.hasPrefix("http") else {
            return (false, "地址需以 http:// 或 https:// 开头")
        }
        var path = "/api/health"
        if !sharecode.isEmpty {
            path += "?sharecode=" + encode(sharecode)
        }
        guard let url = URL(string: base + path) else {
            return (false, "地址格式不正确")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return (true, "连接成功，已保存") }
            return (false, "地址可达但返回异常 (\(status))")
        } catch {
            return (false, "连接失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 带进度的下载

private final class DownloadKit: NSObject, URLSessionDownloadDelegate {

    private let destination: URL
    private let onProgress: ((Int64, Int64) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var pendingError: Error?

    init(destination: URL, onProgress: ((Int64, Int64) -> Void)?) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func start(request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 3600
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: request)
            self.downloadTask = task
            task.resume()
        }
    }

    /// 真实暂停/恢复底层下载任务
    func pause() { downloadTask?.suspend() }
    func resume() { downloadTask?.resume() }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress?(totalBytesWritten, max(0, totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode >= 400 {
            pendingError = APIError(message: "下载失败 (\(http.statusCode))")
            return
        }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.moveItem(at: location, to: destination)
        } catch {
            pendingError = APIError(message: error.localizedDescription)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        self.session = nil
        let continuation = self.continuation
        self.continuation = nil
        if let pendingError = pendingError {
            continuation?.resume(throwing: pendingError)
        } else if let error = error {
            continuation?.resume(throwing: APIError(message: error.localizedDescription))
        } else {
            continuation?.resume(returning: ())
        }
    }
}
