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

    /// 文件行长按操作（居中系统 alert，与账号删除确认一致）
    @State private var menuTarget: QFFile?
    @State private var showFileMenu = false

    @State private var shareTarget: QFFile?
    @State private var sharePassword = ""
    @State private var showShare = false

    /// 文件夹导航方向：进入子页为前向（新页从右滑入、旧页向左滑出），
    /// 返回为后向（父页从左滑入、子页向右滑出）。配合 250ms 原生转场。
    @State private var navigatingForward = true
    /// 切换文件夹期间为 true：新页先显示中性占位，避免旧目录文件闪现、也避免空态文案误闪。
    @State private var folderSwitching = false

    private var currentParentId: Int? { stack.last?.folderId }

    /// 文件夹进出的水平转场：新页从对应方向滑入；旧页立即移除（removal = .identity），
    /// 避免进/出文件夹时旧目录内容残留、与新页交叠迟迟不消失。
    private var folderTransition: AnyTransition {
        if navigatingForward {
            return .asymmetric(insertion: .move(edge: .trailing),
                               removal: .identity)
        } else {
            return .asymmetric(insertion: .move(edge: .leading),
                               removal: .identity)
        }
    }

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
                        SpinningRefreshIcon {
                            _ = Task { await reload() }
                        }
                    }
                )
            )

            searchBar

            // 文件夹内容：以当前文件夹身份驱动 250ms 水平转场。
            // 用 ZStack 让进/出两页在同一区域重叠滑动，呈现出原生 push/pop 观感；
            // id 只随文件夹层级变化，刷新/搜索不动它，因此不会被误触发。
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 12) {
                        if folderSwitching {
                            // 文件夹刚切换、数据尚未回来：显示中性占位，
                            // 既不闪现上一页旧文件，也不误闪"文件夹是空的"文案。
                            Color.clear.frame(height: 320)
                        } else if items.isEmpty && !loading {
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
                .id(stack.last?.id ?? UUID())
                .transition(folderTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MD3.background.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            MDFab(icon: "plus", label: "上传") { showSourceDialog = true }
                .padding(.trailing, 20)
                .padding(.bottom, 100)
        }
        .task { await load(parentId: currentParentId) }
        // 上传选项：系统原生居中弹窗（与设置页退出登录一致），功能与文案不变
        .alert("上传文件", isPresented: $showSourceDialog) {
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
        // 文件长按操作菜单：系统原生居中弹窗（与切换账号删除确认一致），
        // 菜单项复用 fileMenuContent 的同一份逻辑，功能/文案完全不变。
        .alert("文件操作", isPresented: $showFileMenu, presenting: menuTarget) { file in
            if file.isFolder {
                Button("打开") { open(file) }
            } else {
                Button("预览 / 下载") { previewTarget = file }
            }
            Button("分享链接") {
                shareTarget = file
                sharePassword = ""
                showShare = true
            }
            Button("重命名") {
                renameTarget = file
                renameText = file.name
                showRename = true
            }
            Button("删除", role: .destructive) {
                // 稍延迟，等操作菜单收起后再弹居中删除确认，避免呈现冲突
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    deleteTarget = file
                    showDeleteConfirm = true
                }
            }
            Button("取消", role: .cancel) {}
        } message: { file in
            Text(file.name)
        }
        // 删除确认弹窗：系统原生居中弹窗（与设置页退出登录一致），文案/按钮/执行逻辑不变
        .alert("删除确认", isPresented: $showDeleteConfirm) {
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
                    ZStack(alignment: .trailing) {
                        // 轻点打开、长按弹出居中系统操作菜单（与右侧三点菜单内容一致）。
                        // 长按改用 UIKit 原生识别器（FileLongPressDetector），与滚动系统级协调，
                        // 彻底解决 SwiftUI 手势在列表里抢占滚动导致「滑不动」；
                        // 按住变淡、滑动自动恢复，滚动/下拉刷新照常。
                        FileActionRow(
                            file: file,
                            onTap: { open(file) },
                            onLongPress: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                menuTarget = file
                                showFileMenu = true
                            }
                        )

                        // 右侧三点：点击弹出操作菜单（标题/重命名/分享/删除），对齐本行
                        Menu {
                            fileMenuContent(for: file)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MD3.onSurfaceVariant.opacity(0.7))
                                .frame(width: 44, height: 66)
                                .contentShape(Rectangle())
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

    // MARK: 操作菜单（长按与三点按钮共用同一份内容，保证完全一致）

    @ViewBuilder
    private func fileMenuContent(for file: QFFile) -> some View {
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
            // 稍延迟，等操作菜单收起后再弹出居中的删除确认弹窗，避免呈现冲突
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                deleteTarget = file
                showDeleteConfirm = true
            }
        } label: {
            Label("删除", systemImage: "trash")
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
            // 进入子页：前向转场（新页从右滑入），250ms 原生时长。
            // 同一事务内清空旧目录数据并进入切换态：新页先渲染空白占位，
            // 不会拿上一页的 items 闪现；load 回来后再填新数据。
            navigatingForward = true
            withAnimation(.easeInOut(duration: 0.25)) {
                stack.append(FolderPath(folderId: file.id, name: file.name))
                items = []
                folderSwitching = true
            }
            Task { await load(parentId: currentParentId) }
        } else {
            previewTarget = file
        }
    }

    private func goBack() {
        guard stack.count > 1 else { return }
        // 返回父页：后向转场（新页从左滑入、子页向右滑出）。
        // 同样清空当前（子目录）数据并进入切换态，避免返回时旧内容闪现。
        navigatingForward = false
        withAnimation(.easeInOut(duration: 0.25)) {
            stack.removeLast()
            items = []
            folderSwitching = true
        }
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
        // 文件夹切换的数据已（尝试）加载完成，结束切换态，让新页内容显示出来。
        // 与转场动画同时收尾，避免占位停留过久。
        withAnimation(.easeOut(duration: 0.12)) { folderSwitching = false }
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

/// 文件行交互：轻点打开/预览，长按弹出居中系统操作菜单，按住时名字变淡。
///
/// 关键设计（彻底解决「滑动滑不动 / 一滑就变灰」与「长按要变淡 + 弹菜单」的冲突）：
/// - 长按检测改用 UIKit 原生 `UILongPressGestureRecognizer`（见 FileLongPressDetector），
///   它与 UIScrollView 滚动手势经过系统级协调：手指滑动时系统判定为滚动、长按自动失败，
///   既不抢占滚动、也不会一滑就变灰；而纯 SwiftUI 的 LongPressGesture 在列表里
///   会与 ScrollView 竞争，是前几版「滑不动」的根因。
/// - `cancelsTouchesInView = false` + `shouldRecognizeSimultaneouslyWith = true`：
///   长按识别器不吞掉点击/滚动，页面照常滚动、下拉刷新照常工作。
/// - 按住变淡由 `.began` 置 true、`.ended/.cancelled/.failed` 置 false 驱动，
///   只在真正按住满 0.5s 且未滑动时才变淡，与切换账号页账号行观感一致。
/// - 长按命中后 `suppressTap` 吞掉随之而来的那次点击，避免松手误打开/误进文件夹。
private struct FileActionRow: View {
    let file: QFFile
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var pressing = false
    @State private var suppressTap = false

    var body: some View {
        HStack(spacing: 0) {
            FileRow(file: file, showsChevron: false, dimmed: pressing)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .overlay(
            FileLongPressDetector(pressing: $pressing) {
                suppressTap = true
                onLongPress()
                // 兜底清除：alert 弹出时 tap 回调可能不会抵达，避免吞掉下次正常点击
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    suppressTap = false
                }
            }
        )
        .onTapGesture {
            if suppressTap {
                suppressTap = false
                return
            }
            onTap()
        }
    }
}

/// 用 UIKit 原生长按识别器承载「按住变淡 + 长按弹菜单」。
/// 原生识别器与 UIScrollView 有系统级手势协调，按在文件上滑动时页面照常滚动，
/// 不会出现纯 SwiftUI LongPressGesture 在列表里抢占滚动导致「滑不动」的问题。
private struct FileLongPressDetector: UIViewRepresentable {
    @Binding var pressing: Bool
    let onLongPress: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let lp = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handle(_:)))
        lp.minimumPressDuration = 0.5
        lp.allowableMovement = 10
        lp.cancelsTouchesInView = false  // 不吞掉点击与滚动
        lp.delegate = context.coordinator
        view.addGestureRecognizer(lp)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onLongPress = onLongPress
        context.coordinator.pressing = $pressing
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onLongPress: (() -> Void)?
        var pressing: Binding<Bool>?
        private var didTrigger = false

        @objc func handle(_ gr: UILongPressGestureRecognizer) {
            switch gr.state {
            case .began:
                didTrigger = true
                pressing?.wrappedValue = true
                onLongPress?()
            case .ended, .cancelled, .failed:
                if didTrigger { pressing?.wrappedValue = false }
                didTrigger = false
            default:
                break
            }
        }

        // 与父级 ScrollView 滚动手势、子视图点击手势同时识别，互不吞掉
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
