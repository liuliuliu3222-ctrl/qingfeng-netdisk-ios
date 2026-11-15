import UIKit
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// UIKit 文件选择器，解决 SwiftUI fileImporter 卡住的问题
struct DocumentPicker: UIViewControllerRepresentable {
    let allowsMultiple: Bool
    let onPicked: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPicked(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        }
    }
}

struct FolderPath: Identifiable, Hashable {
    let id = UUID()
    let folderId: Int?
    let name: String
}

struct FilesView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var stack: [FolderPath] = [FolderPath(folderId: nil, name: "全部文件")]
    @State private var items: [QFFile] = []
    @State private var loading = false

    @State private var searchText = ""
    @State private var searchMode = false
    @State private var searchTask: Task<Void, Never>?

    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showSourceDialog = false
    @State private var showTrash = false

    @State private var previewTarget: QFFile?

    @State private var showNewFolder = false
    @State private var newFolderName = ""

    @State private var renameTarget: QFFile?
    @State private var renameText = ""
    @State private var showRename = false

    @State private var deleteTarget: QFFile?
    @State private var showDeleteConfirm = false

    @State private var shareTarget: QFFile?
    @State private var sharePassword = ""
    @State private var showShare = false

    private var currentParentId: Int? { stack.last?.folderId }

    private var pathText: String {
        stack.map { $0.name }.joined(separator: " / ")
    }

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(
                title: "文件",
                subtitle: pathText,
                showsBack: stack.count > 1,
                onBack: { goBack() },
                trailing: AnyView(
                    HStack(spacing: 0) {
                        MDIconButton(icon: "folder.badge.plus") { showNewFolder = true }
                        MDIconButton(icon: "trash") { showTrash = true }
                        MDIconButton(icon: "arrow.clockwise") {
                            Task { await reload() }
                        }
                    }
                )
            )

            searchBar

            ScrollView {
                VStack(spacing: 12) {
                    if items.isEmpty && !loading {
                        MDEmptyState(icon: searchMode ? "magnifyingglass" : "folder",
                                     title: searchMode ? "没有匹配的文件" : "这个文件夹还是空的",
                                     detail: searchMode ? nil : "点右下角按钮上传文件，或新建文件夹")
                            .frame(minHeight: 320)
                    } else {
                        fileList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
            .refreshable { await reload() }
        }
        .background(MD3.background.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            MDFab(icon: "plus", label: "上传") { showSourceDialog = true }
                .padding(.trailing, 20)
                .padding(.bottom, 100)
        }
        .task { await load(parentId: currentParentId) }
        .confirmationDialog("上传文件", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("从「文件」选择") { showFilePicker = true }
            Button("从「照片」选择") { showPhotoPicker = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("上传到：\(stack.last?.name ?? "全部文件")")
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker(allowsMultiple: true) { urls in
                upload(urls: urls)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker,
                      selection: $photoItems,
                      maxSelectionCount: 10,
                      matching: .any(of: [.images, .videos]))
        .onChange(of: photoItems) { newItems in
            guard !newItems.isEmpty else { return }
            handlePhotos(newItems)
        }
        .sheet(isPresented: $showTrash) {
            TrashView()
        }
        .sheet(item: $previewTarget) { file in
            PreviewView(file: file)
        }
        .alert("新建文件夹", isPresented: $showNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") { createFolder() }
        } message: {
            Text("将在「\(stack.last?.name ?? "全部文件")」下创建")
        }
        .alert("重命名", isPresented: $showRename) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { performRename() }
        } message: {
            Text(renameTarget?.name ?? "")
        }
        .alert("分享「\(shareTarget?.name ?? "")」", isPresented: $showShare) {
            TextField("访问密码（选填）", text: $sharePassword)
            Button("取消", role: .cancel) { sharePassword = "" }
            Button("创建") { createShare() }
        } message: {
            Text("将生成分享链接并复制到剪贴板")
        }
        .confirmationDialog("删除确认", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("移入回收站", role: .destructive) { performDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定把「\(deleteTarget?.name ?? "")」移入回收站？文件夹将连同其中内容一起移入，可在回收站内还原。")
        }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: 搜索栏

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(MD3.onSurfaceVariant)
            TextField("搜索文件", text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(MD3.onSurface)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(MD3.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(MD3.surfaceContainerHigh)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onChange(of: searchText) { value in
            searchTask?.cancel()
            let keyword = value.trimmingCharacters(in: .whitespacesAndNewlines)
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 420_000_000)
                if Task.isCancelled { return }
                await runSearch(keyword)
            }
        }
    }

    // MARK: 列表

    private var fileList: some View {
        MDCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, file in
                    Button {
                        open(file)
                    } label: {
                        FileRow(file: file)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if file.isFolder {
                            Button {
                                open(file)
                            } label: {
                                Label("打开", systemImage: "folder")
                            }
                        } else {
                            Button {
                                previewTarget = file
                            } label: {
                                Label("预览 / 下载", systemImage: "eye")
                            }
                        }
                        Button {
                            shareTarget = file
                            sharePassword = ""
                            showShare = true
                        } label: {
                            Label("分享链接", systemImage: "link")
                        }
                        Button {
                            renameTarget = file
                            renameText = file.name
                            showRename = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteTarget = file
                            showDeleteConfirm = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }

                    if index < items.count - 1 {
                        Divider()
                            .overlay(MD3.outlineVariant)
                            .padding(.leading, 72)
                    }
                }
            }
        }
    }

    // MARK: 动作

    private func open(_ file: QFFile) {
        if file.isFolder {
            if searchMode {
                searchText = ""
                searchMode = false
                stack = [FolderPath(folderId: nil, name: "全部文件")]
            }
            stack.append(FolderPath(folderId: file.id, name: file.name))
            Task { await load(parentId: currentParentId) }
        } else {
            previewTarget = file
        }
    }

    private func goBack() {
        guard stack.count > 1 else { return }
        stack.removeLast()
        Task { await load(parentId: currentParentId) }
    }

    private func load(parentId: Int?) async {
        loading = true
        do {
            // 每次都向服务端重新取列表，上传新文件后下拉刷新一定拿到最新数据
            let list = try await ApiClient.shared.list(parentId: parentId)
            // 文件夹排在前面，然后按名称排序
            items = list.sorted { a, b in
                if a.isFolder != b.isFolder {
                    return a.isFolder && !b.isFolder
                }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
        } catch {
            // 读取失败（含系统取消）：保留现有列表，绝不清空，也不弹任何提示
        }
        loading = false
    }

    private func reload() async {
        // 下拉刷新 / 顶部刷新按钮：始终重新请求，并保持当前搜索状态
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if searchMode && !keyword.isEmpty {
            await runSearch(keyword)
        } else {
            await load(parentId: currentParentId)
        }
    }

    private func runSearch(_ keyword: String) async {
        guard !keyword.isEmpty else {
            searchMode = false
            await load(parentId: currentParentId)
            return
        }
        loading = true
        searchMode = true
        do {
            // 重新向服务端搜索，保证刷新能拿到最新结果
            items = try await ApiClient.shared.search(keyword)
        } catch {
            // 失败或被取消时保留现有结果，不清空、不弹提示
        }
        loading = false
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let parent = currentParentId
        newFolderName = ""
        Task {
            do {
                try await ApiClient.shared.mkdir(name: name, parentId: parent)
                ToastCentre.shared.show("已创建：\(name)")
                await load(parentId: parent)
            } catch {
                ToastCentre.shared.show(error.localizedDescription)
            }
        }
    }

    private func performRename() {
        guard let target = renameTarget else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            do {
                try await ApiClient.shared.rename(id: target.id, name: name)
                ToastCentre.shared.show("已重命名")
                await reload()
            } catch {
                ToastCentre.shared.show(error.localizedDescription)
            }
        }
    }

    private func performDelete() {
        guard let target = deleteTarget else { return }
        Task {
            do {
                try await ApiClient.shared.delete(id: target.id)
                ToastCentre.shared.show("已移入回收站")
                await reload()
            } catch {
                ToastCentre.shared.show(error.localizedDescription)
            }
        }
    }

    private func createShare() {
        guard let target = shareTarget else { return }
        let password = sharePassword.trimmingCharacters(in: .whitespacesAndNewlines)
        sharePassword = ""
        Task {
            do {
                let sharePath = try await ApiClient.shared.shareCreate(id: target.id,
                                                                      password: password.isEmpty ? nil : password,
                                                                      expireHours: nil)
                var url = AppSettings.server + sharePath
                let code = AppSettings.sharecode
                if !code.isEmpty {
                    url += (sharePath.contains("?") ? "&" : "?") + "sharecode=" + ApiClient.encode(code)
                }
                UIPasteboard.general.string = url
                ToastCentre.shared.show("链接已复制：\(url)")
            } catch {
                ToastCentre.shared.show(error.localizedDescription)
            }
        }
    }

    private func upload(urls: [URL]) {
        guard !urls.isEmpty else { return }
        ToastCentre.shared.show("开始上传 \(urls.count) 个文件...")
        let parent = currentParentId
        Task {
            for url in urls {
                let name = url.lastPathComponent.isEmpty ? "未命名文件" : url.lastPathComponent
                do {
                    try await Uploader.upload(fileURL: url, displayName: name, parentId: parent)
                    // 上传完后删除临时文件
                    try? FileManager.default.removeItem(at: url)
                    ToastCentre.shared.show("已上传：\(name)")
                } catch {
                    ToastCentre.shared.show("\(name) 上传失败：\(error.localizedDescription)")
                }
            }
            await load(parentId: parent)
            await session.refreshProfile()
        }
    }

    private func handlePhotos(_ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty else { return }
        photoItems = []
        let parent = currentParentId
        Task {
            for item in picked {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first
                let ext = type?.preferredFilenameExtension ?? "bin"
                let name = "photo_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).\(ext)"
                do {
                    try await Uploader.upload(data: data, displayName: name, parentId: parent)
                    ToastCentre.shared.show("已上传：\(name)")
                } catch {
                    ToastCentre.shared.show("\(name) 上传失败：\(error.localizedDescription)")
                }
            }
            await load(parentId: parent)
            await session.refreshProfile()
        }
    }
}
