import SwiftUI
import UIKit

/// 文件列表行：图标或缩略图 + 名称 + 元信息
struct FileRow: View {

    let file: QFFile
    var showsChevron: Bool = true
    /// 长按时文件名轻微变淡（与切换账号账号行、首页最近使用的按压观感一致）
    var dimmed: Bool = false

    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            iconView

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MD3.onSurface)
                    .opacity(dimmed ? 0.45 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: dimmed)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(MD3.onSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if showsChevron {
                Image(systemName: file.isFolder ? "chevron.right" : "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MD3.onSurfaceVariant.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .contentShape(Rectangle())
        .task(id: file.id) {
            guard !file.isFolder, file.hasThumb else { return }
            thumbnail = await ThumbnailStore.shared.image(for: file.id)
        }
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MD3.primaryContainer)
                .frame(width: 42, height: 42)
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: file.kind.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MD3.primary)
            }
        }
    }

    private var subtitle: String {
        if let trashedAt = file.trashedAt {
            let size = file.isFolder ? "文件夹" : ByteText.string(file.size)
            return "\(size) · 删除于 \(trashedAt.replacingOccurrences(of: "T", with: " "))"
        }
        return file.isFolder ? "文件夹" : ByteText.string(file.size)
    }
}

/// 列表容器：把一组文件渲染成 MD3 卡片列表
struct FileListCard: View {

    let files: [QFFile]
    let onTap: (QFFile) -> Void
    let actions: (QFFile) -> AnyView

    var body: some View {
        MDCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    Button {
                        onTap(file)
                    } label: {
                        FileRow(file: file)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        actions(file)
                    }

                    if index < files.count - 1 {
                        Divider()
                            .overlay(MD3.outlineVariant)
                            .padding(.leading, 72)
                    }
                }
            }
        }
    }
}
