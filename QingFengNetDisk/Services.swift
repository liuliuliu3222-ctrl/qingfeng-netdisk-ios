import Foundation
import Combine
import UIKit
import UserNotifications

// MARK: - 传输任务中心（对应 TransferManager）

@MainActor
final class TransferStore: ObservableObject {

    static let shared = TransferStore()

    @Published private(set) var tasks: [TransferTask] = []

    /// 被暂停的任务 id。上传/下载协程在每步推进前查询，暂停时原地挂起等待恢复。
    private var pausedIDs: Set<UUID> = []
    private let maxKeep = 50

    private init() {}

    func begin(kind: TransferTask.Kind, name: String, total: Int64) -> UUID {
        let task = TransferTask(kind: kind, name: name, total: total)
        tasks.insert(task, at: 0)
        if tasks.count > maxKeep {
            tasks.removeLast(tasks.count - maxKeep)
        }
        return task.id
    }

    /// 记录下载任务的落盘路径，供「删除本地文件」使用
    func setLocalPath(id: UUID, path: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].localPath = path
    }

    func update(id: UUID, done: Int64, total: Int64) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].done = done
        if total > 0 {
            tasks[index].total = total
        }
    }

    func finish(id: UUID, state: TransferTask.State, message: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        // 已暂停的任务不接收完成态，保持暂停显示，直到用户删除或恢复
        if pausedIDs.contains(id) { return }
        tasks[index].state = state
        tasks[index].message = message
        if state == .done {
            tasks[index].done = tasks[index].total
        }
    }

    func runningCount() -> Int {
        tasks.filter { $0.state == .running }.count
    }

    func items(kind: TransferTask.Kind) -> [TransferTask] {
        tasks.filter { $0.kind == kind }
    }

    // MARK: - 暂停 / 恢复

    func isPaused(_ id: UUID) -> Bool { pausedIDs.contains(id) }

    /// 暂停所有进行中的任务（UI 立即显示「已暂停」，进度冻结）
    func pauseAll() {
        for index in tasks.indices where tasks[index].state == .running {
            tasks[index].state = .paused
            pausedIDs.insert(tasks[index].id)
        }
    }

    /// 恢复所有暂停的任务回到进行中
    func resumeAll() {
        for index in tasks.indices where tasks[index].state == .paused {
            tasks[index].state = .running
            pausedIDs.remove(tasks[index].id)
        }
    }

    /// 传输协程在推进前调用：暂停时挂起，恢复后返回 true；任务被删除则返回 false 应中止
    func waitIfPaused(_ id: UUID) async -> Bool {
        while isPaused(id) {
            guard tasks.contains(where: { $0.id == id }) else { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return tasks.contains(where: { $0.id == id })
    }

    // MARK: - 删除（本地文件 + 列表记录）

    /// 删除单个任务：先删除已落盘的本地文件，再从列表移除
    func delete(id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        deleteLocalFile(of: task)
        pausedIDs.remove(id)
        tasks.removeAll { $0.id == id }
    }

    /// 清空全部任务：删除所有已落盘的本地文件，再清空列表
    func deleteAll() {
        for task in tasks { deleteLocalFile(of: task) }
        pausedIDs.removeAll()
        tasks.removeAll()
    }

    private func deleteLocalFile(of task: TransferTask) {
        guard let path = task.localPath, !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - 本地通知（替代 Android 常驻通知栏进度）

enum Notifier {

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

// MARK: - 分片上传（对应 Uploader，5MB 一片）

enum Uploader {

    static func upload(fileURL: URL, displayName: String, parentId: Int?) async throws {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { fileURL.stopAccessingSecurityScopedResource() }
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let chunk = Int64(AppSettings.chunkSizeMB) * 1024 * 1024
        let totalChunks = max(1, Int((size + chunk - 1) / chunk))

        let taskId = await TransferStore.shared.begin(kind: .upload, name: displayName, total: size)

        do {
            let uploadId = try await ApiClient.shared.uploadInit(name: displayName,
                                                                size: size,
                                                                parentId: parentId,
                                                                totalChunks: totalChunks)
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            var sent: Int64 = 0
            for index in 0..<totalChunks {
                // 暂停时原地挂起；任务被删除则中止上传
                guard await TransferStore.shared.waitIfPaused(taskId) else { return }
                let data = try handle.read(upToCount: ApiClient.chunkSize) ?? Data()
                if data.isEmpty { break }
                try await ApiClient.shared.uploadChunk(uploadId: uploadId, index: index, data: data)
                sent += Int64(data.count)
                await TransferStore.shared.update(id: taskId, done: sent, total: size)
            }
            try await ApiClient.shared.uploadComplete(uploadId: uploadId)
            await TransferStore.shared.finish(id: taskId, state: .done, message: "")
            Notifier.post(title: "上传完成", body: displayName)
        } catch {
            await TransferStore.shared.finish(id: taskId,
                                              state: .failed,
                                              message: error.localizedDescription)
            throw error
        }
    }

    /// 供 PhotosPicker 使用：先落到临时文件，再走同一套分片逻辑
    static func upload(data: Data, displayName: String, parentId: Int?) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("qf_uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(displayName)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try await upload(fileURL: url, displayName: displayName, parentId: parentId)
    }
}

// MARK: - 下载落盘

enum Downloader {

    static func destination(for name: String, id: Int) -> URL {
        let folder = documentsFolder().appendingPathComponent("下载", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name.isEmpty ? "file_\(id)" : name
        return folder.appendingPathComponent(safeName)
    }

    static func documentsFolder() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func download(file: QFFile) async throws -> URL {
        let target = destination(for: file.name, id: file.id)
        let taskId = await TransferStore.shared.begin(kind: .download, name: file.name, total: file.size)
        await TransferStore.shared.setLocalPath(id: taskId, path: target.path)
        do {
            try await ApiClient.shared.download(id: file.id, to: target) { done, total in
                Task { @MainActor in
                    TransferStore.shared.update(id: taskId, done: done, total: total)
                }
            }
            await TransferStore.shared.finish(id: taskId, state: .done, message: "")
            Notifier.post(title: "下载完成", body: file.name)
            return target
        } catch {
            await TransferStore.shared.finish(id: taskId,
                                              state: .failed,
                                              message: error.localizedDescription)
            throw error
        }
    }
}

// MARK: - 缩略图缓存（对应 Thumbs）

@MainActor
final class ThumbnailStore {

    static let shared = ThumbnailStore()

    private let memory = NSCache<NSNumber, UIImage>()
    private let folder: URL
    private var running: Set<Int> = []

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        memory.countLimit = 200
    }

    func image(for id: Int) async -> UIImage? {
        let key = NSNumber(value: id)
        if let cached = memory.object(forKey: key) {
            return cached
        }
        let file = folder.appendingPathComponent("\(id).jpg")
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key)
            return image
        }
        if running.contains(id) { return nil }
        running.insert(id)
        defer { running.remove(id) }

        do {
            let data = try await ApiClient.shared.fetchThumb(id: id)
            guard let image = UIImage(data: data) else { return nil }
            memory.setObject(image, forKey: key)
            try? data.write(to: file)
            return image
        } catch {
            return nil
        }
    }

    func clearDisk() {
        let manager = FileManager.default
        if let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in files {
                try? manager.removeItem(at: file)
            }
        }
        memory.removeAllObjects()
    }
}

// MARK: - 会话

@MainActor
final class SessionStore: ObservableObject {

    @Published var token: String
    @Published var me: QFMe
    @Published var lastError: String?
    /// 已保存账号列表的版本号：增删账号后通知界面刷新
    @Published private(set) var accountsRevision = 0

    init() {
        token = AppSettings.token
        me = AppSettings.cachedMe
    }

    var isLoggedIn: Bool { !token.isEmpty }

    func signIn(token: String, username: String, password: String = "") {
        AppSettings.token = token
        AppSettings.username = username
        // 记住账号 + 密码，供下次一键切换
        AppSettings.rememberAccount(username: username, password: password)
        accountsRevision += 1
        self.token = token
        var fresh = QFMe()
        fresh.username = username
        me = fresh
    }

    /// 一键切换到已保存的账号（无需重新输入密码）
    func switchAccount(to username: String) {
        let password = AppSettings.storedPassword(for: username)
        guard !password.isEmpty else {
            lastError = "该账号未保存密码，请重新登录"
            return
        }
        Task {
            do {
                let token = try await ApiClient.shared.auth(username: username,
                                                            password: password,
                                                            register: false)
                AppSettings.token = token
                AppSettings.username = username
                AppSettings.rememberAccount(username: username, password: password)
                self.token = token
                var fresh = QFMe()
                fresh.username = username
                me = fresh
                await refreshProfile()
                ToastCentre.shared.show("已切换到 \(username)")
            } catch {
                // 密码失效时保留账号条目，让用户走登录页
                ToastCentre.shared.show("切换失败：\(error.localizedDescription)")
            }
        }
    }

    /// 删除某个已保存的账号；若删除的是当前账号则退出登录
    func deleteSavedAccount(_ username: String) {
        AppSettings.forgetAccount(username)
        accountsRevision += 1
        if username == AppSettings.username || AppSettings.username.isEmpty {
            AppSettings.clearAuth()
            token = ""
            me = QFMe()
        }
    }

    func refreshProfile() async {
        guard isLoggedIn else { return }
        do {
            let profile = try await ApiClient.shared.me()
            me = profile
            AppSettings.cache(profile)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func logout() {
        AppSettings.clearAuth()
        token = ""
        me = QFMe()
    }
}
