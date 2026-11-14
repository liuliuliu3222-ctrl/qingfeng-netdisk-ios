import SwiftUI
import AVKit
import QuickLook
import UIKit

struct PreviewView: View {

    let file: QFFile

    @Environment(\.dismiss) private var dismiss

    @State private var textContent: String?
    @State private var loading = false
    @State private var downloadedURL: URL?
    @State private var showQuickLook = false
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(
                title: file.name,
                subtitle: "\(file.kindTitle) · \(ByteText.string(file.size))",
                showsBack: true,
                onBack: { dismiss() },
                trailing: AnyView(
                    MDIconButton(icon: "square.and.arrow.down") { download() }
                )
            )

            content
        }
        .background(MD3.background.ignoresSafeArea())
        .task { await prepare() }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .sheet(isPresented: $showQuickLook) {
            if let url = downloadedURL {
                QuickLookView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch file.kind {
        case .image:
            imageContent
        case .video:
            videoContent
        case .audio:
            audioContent
        case .text:
            textContent_
        default:
            unsupportedContent
        }
    }

    // MARK: 图片

    private var imageContent: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                AsyncImage(url: ApiClient.shared.streamingURL(id: file.id, preview: true)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: proxy.size.width)
                    case .failure:
                        MDEmptyState(icon: "photo",
                                     title: "图片加载失败",
                                     detail: "检查网络或服务器地址")
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    default:
                        ProgressView("加载中…")
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 视频

    private var videoContent: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .frame(maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
    }

    // MARK: 音频

    private var audioContent: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(MD3.primaryContainer)
                    .frame(width: 168, height: 168)
                Image(systemName: "waveform")
                    .font(.system(size: 62, weight: .light))
                    .foregroundStyle(MD3.primary)
                    .scaleEffect(playing ? 1.06 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: playing)
            }
            Text(file.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MD3.onSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                guard let player = player else { return }
                if playing {
                    player.pause()
                } else {
                    player.play()
                }
                playing.toggle()
            } label: {
                ZStack {
                    Circle().fill(MD3.primary).frame(width: 64, height: 64)
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(MD3.onPrimary)
                        .offset(x: playing ? 0 : 2)
                }
            }
            .buttonStyle(.plain)

            Text("音频：\(file.name)")
                .font(.system(size: 12))
                .foregroundStyle(MD3.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: 文本

    private var textContent_: some View {
        Group {
            if file.size > 2 * 1024 * 1024 {
                MDEmptyState(icon: "doc.plaintext",
                             title: "文本过大，仅支持 2MB 以内预览",
                             detail: "可以下载后查看")
            } else if let text = textContent {
                ScrollView {
                    Text(text)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(MD3.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .textSelection(.enabled)
                }
                .background(MD3.surface)
            } else if let error = errorText {
                MDEmptyState(icon: "exclamationmark.triangle", title: "读取失败", detail: error)
            } else {
                ProgressView("读取中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: 其它类型

    private var unsupportedContent: some View {
        VStack(spacing: 18) {
            MDEmptyState(icon: file.kind.symbol,
                         title: "暂不支持预览，可下载",
                         detail: "下载后可用「文件」App 打开")
            MDPrimaryButton(title: loading ? "下载中…" : "下载", icon: "square.and.arrow.down", enabled: !loading) {
                download()
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 逻辑

    private func prepare() async {
        switch file.kind {
        case .video, .audio:
            if let url = ApiClient.shared.streamingURL(id: file.id, preview: true) {
                player = AVPlayer(url: url)
            }
        case .text:
            guard file.size <= 2 * 1024 * 1024 else { return }
            do {
                let data = try await ApiClient.shared.fetchPreview(id: file.id)
                textContent = String(data: data, encoding: .utf8) ?? "（无法以 UTF-8 解码）"
            } catch {
                errorText = error.localizedDescription
            }
        default:
            break
        }
    }

    private func download() {
        guard !loading else { return }
        loading = true
        Task {
            do {
                let url = try await Downloader.download(file: file)
                downloadedURL = url
                showQuickLook = true
                ToastCentre.shared.show("已保存到「文件」- 清风网盘/下载")
            } catch {
                ToastCentre.shared.show(error.localizedDescription)
            }
            loading = false
        }
    }
}

// MARK: - QuickLook（对应 Android 里用系统组件打开未知类型）

struct QuickLookView: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL as QLPreviewItem
        }
    }
}

extension QFFile {
    var kindTitle: String {
        switch kind {
        case .folder: return "文件夹"
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "音频"
        case .text: return "文本"
        case .pdf: return "PDF"
        case .archive: return "压缩包"
        case .document: return "文档"
        case .sheet: return "表格"
        case .other: return "文件"
        }
    }
}
