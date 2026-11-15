import UIKit
import SwiftUI

// MARK: - 色值工具

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// MARK: - Material Design 3 语义色板
// 取自原 APK res/values/colors.xml，并补充暗色映射

enum MD3 {
    static let primary = Color.adaptive(light: 0x2FAE7A, dark: 0x6FD9AC)
    static let onPrimary = Color.adaptive(light: 0xFFFFFF, dark: 0x00382A)
    static let primaryContainer = Color.adaptive(light: 0xE6F5EE, dark: 0x0F3D2E)
    static let onPrimaryContainer = Color.adaptive(light: 0x0F3D2E, dark: 0xD5F4E6)

    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x121715)
    static let surfaceContainerLowest = Color.adaptive(light: 0xFFFFFF, dark: 0x0D1210)
    static let surfaceContainerLow = Color.adaptive(light: 0xF7F9F8, dark: 0x181F1C)
    static let surfaceContainer = Color.adaptive(light: 0xF2F5F3, dark: 0x1D2621)
    static let surfaceContainerHigh = Color.adaptive(light: 0xEBF0EC, dark: 0x242E29)
    static let surfaceContainerHighest = Color.adaptive(light: 0xE3E9E5, dark: 0x2B3631)
    static let background = Color.adaptive(light: 0xF5F7F6, dark: 0x0B0F0D)

    static let onSurface = Color.adaptive(light: 0x1F2D28, dark: 0xE3EAE6)
    static let onSurfaceVariant = Color.adaptive(light: 0x5C6B64, dark: 0xA7B4AE)
    static let outline = Color.adaptive(light: 0xB8C4BD, dark: 0x4C5952)
    static let outlineVariant = Color.adaptive(light: 0xE4EAE6, dark: 0x2F3A34)

    static let error = Color.adaptive(light: 0xE5533D, dark: 0xFFB4A6)
    static let errorContainer = Color.adaptive(light: 0xFDE7E3, dark: 0x5C1B12)
    static let onErrorContainer = Color.adaptive(light: 0x7A1C0E, dark: 0xFFDAD3)

    static let success = Color.adaptive(light: 0x2FAE7A, dark: 0x6FD9AC)

    // 圆角与间距，遵循 MD3 shape scale
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusExtraLarge: CGFloat = 28
}

// MARK: - 通用修饰

struct MDFill: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func mdFill(_ color: Color, radius: CGFloat = MD3.radiusLarge) -> some View {
        modifier(MDFill(color: color, radius: radius))
    }
}

// MARK: - 按钮

struct MDPrimaryButton: View {
    let title: String
    var icon: String?
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(MD3.onPrimary)
            .background(enabled ? MD3.primary : MD3.onSurfaceVariant.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct MDTextButton: View {
    let title: String
    var tint: Color = MD3.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct MDIconButton: View {
    let icon: String
    var tint: Color = MD3.onSurfaceVariant
    var size: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 卡片

struct MDCard<Content: View>: View {
    var color: Color = MD3.surface
    var radius: CGFloat = MD3.radiusLarge
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(MD3.outlineVariant, lineWidth: 1)
            )
    }
}

// MARK: - 顶部应用栏（MD3 TopAppBar）

struct MDTopAppBar: View {
    let title: String
    var subtitle: String?
    var showsBack: Bool = false
    var onBack: (() -> Void)?
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 8) {
            if showsBack {
                MDIconButton(icon: "chevron.left", tint: MD3.onSurface) {
                    onBack?()
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(MD3.onSurface)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(MD3.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let trailing = trailing { trailing }
        }
        .padding(.horizontal, showsBack ? 8 : 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(MD3.background)
    }
}

// MARK: - 悬浮操作按钮（MD3 FAB）

struct MDFab: View {
    let icon: String
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                if let label = label {
                    Text(label).font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(MD3.onPrimaryContainer)
            .padding(.horizontal, label == nil ? 18 : 20)
            .frame(height: 56)
            .background(MD3.primaryContainer)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 环形进度（对应 RingView）

struct RingProgress: View {
    var fraction: Double
    var lineWidth: CGFloat = 10
    var tint: Color = MD3.primary
    var track: Color = MD3.surfaceContainerHighest

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: fraction)
        }
    }
}

// MARK: - 空状态

struct MDEmptyState: View {
    let icon: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(MD3.onSurfaceVariant.opacity(0.6))
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MD3.onSurfaceVariant)
            if let detail = detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(MD3.onSurfaceVariant.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - 输入框（MD3 Outlined TextField）

struct MDTextField: View {
    let title: String
    @Binding var text: String
    var icon: String?
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MD3.onSurfaceVariant)
            HStack(spacing: 10) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(MD3.onSurfaceVariant)
                }
                Group {
                    if secure {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .font(.system(size: 16))
                .foregroundStyle(MD3.onSurface)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(MD3.surfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: MD3.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MD3.radiusMedium, style: .continuous)
                    .stroke(MD3.outlineVariant, lineWidth: 1)
            )
        }
    }
}

// MARK: - Toast（iOS 无系统 Toast）

final class ToastCentre: ObservableObject {
    static let shared = ToastCentre()

    @Published private(set) var message: String?
    private var stamp = 0

    private init() {}

    /// 可在任意线程调用，内部切回主线程刷新
    func show(_ text: String?) {
        guard let text = text, !text.isEmpty else { return }
        DispatchQueue.main.async {
            self.message = text
            self.stamp += 1
            let current = self.stamp
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                if self.stamp == current {
                    self.message = nil
                }
            }
        }
    }
}

/// 与应用品牌一致的提示条，替代原先的系统黑色 Toast。
/// 背景用 MD3.primary 品牌绿、文字与图标用 MD3.onPrimary，深浅色自动适配；
/// 圆角、柔光阴影与全局 MD3 组件（主按钮、Chip）保持同一套规范。
struct MDToast: View {
    let message: String
    var icon: String = "info.circle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(MD3.onPrimary)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: MD3.radiusLarge, style: .continuous)
                .fill(MD3.primary)
        )
        .shadow(color: MD3.primary.opacity(0.30), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 28)
    }
}

struct ToastOverlay: View {
    @ObservedObject var centre = ToastCentre.shared

    var body: some View {
        VStack {
            Spacer()
            if let message = centre.message {
                MDToast(message: message)
                    .padding(.bottom, 96)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: centre.message)
        .allowsHitTesting(false)
    }
}

// MARK: - 列表行

struct MDRow: View {
    let icon: String
    var iconTint: Color = MD3.onPrimaryContainer
    var iconBackground: Color = MD3.primaryContainer
    let title: String
    var subtitle: String?
    var trailingText: String?
    var showsChevron: Bool = true
    var tint: Color = MD3.onSurface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconBackground)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(iconTint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tint)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(MD3.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if let trailingText = trailingText {
                    Text(trailingText)
                        .font(.system(size: 13))
                        .foregroundStyle(MD3.onSurfaceVariant)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MD3.onSurfaceVariant.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
