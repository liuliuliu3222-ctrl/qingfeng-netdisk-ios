import SwiftUI

struct MemberSheet: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var users: [QFAdminUser] = []
    @State private var loadingUsers = false
    @State private var quotaUser = ""
    @State private var quotaGB = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(title: "会员中心",
                       subtitle: "升级会员请联系管理员",
                       showsBack: true,
                       onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 14) {
                    currentCard
                    tiersCard
                    if session.me.isAdmin {
                        adminCard
                    }
                    Text("等级与配额由服务端下发，本地不做缓存修改。")
                        .font(.system(size: 11))
                        .foregroundStyle(MD3.onSurfaceVariant.opacity(0.8))
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
            }
        }
        .background(MD3.background.ignoresSafeArea())
        .task { await refreshAll() }
    }

    // MARK: 当前状态

    private var currentCard: some View {
        MDCard(radius: MD3.radiusExtraLarge, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("当前等级：\(session.me.tierName)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MD3.onSurface)
                    Spacer()
                    if session.me.isAdmin {
                        Text("管理员")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MD3.onPrimaryContainer)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(MD3.primaryContainer)
                            .clipShape(Capsule())
                    }
                }
                Text("已用 \(ByteText.string(session.me.usedBytes)) / \(ByteText.string(session.me.quotaBytes))")
                    .font(.system(size: 12))
                    .foregroundStyle(MD3.onSurfaceVariant)
                ProgressView(value: session.me.fraction)
                    .tint(MD3.primary)
            }
        }
    }

    private var tiersCard: some View {
        MDCard(padding: 0) {
            VStack(spacing: 0) {
                if session.me.tiers.isEmpty {
                    Text("（暂无等级信息）")
                        .font(.system(size: 13))
                        .foregroundStyle(MD3.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(Array(session.me.tiers.enumerated()), id: \.element.id) { index, tier in
                        HStack(spacing: 12) {
                            Image(systemName: tier.name == session.me.tierName ? "checkmark.seal.fill" : "seal")
                                .font(.system(size: 16))
                                .foregroundStyle(tier.name == session.me.tierName ? MD3.primary : MD3.onSurfaceVariant)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tier.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(MD3.onSurface)
                                Text(ByteText.string(tier.quotaBytes))
                                    .font(.system(size: 12))
                                    .foregroundStyle(MD3.onSurfaceVariant)
                            }
                            Spacer()
                            if tier.name == session.me.tierName {
                                Text("当前")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(MD3.primary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if index < session.me.tiers.count - 1 {
                            Divider().overlay(MD3.outlineVariant).padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }

    // MARK: 管理员

    private var adminCard: some View {
        MDCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 14))
                        .foregroundStyle(MD3.primary)
                    Text("管理员：调整用户配额")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MD3.onSurface)
                    Spacer()
                    if loadingUsers { ProgressView().scaleEffect(0.7) }
                }

                MDTextField(title: "用户名", text: $quotaUser, icon: "person", submitLabel: .next)
                MDTextField(title: "空间大小（GB）", text: $quotaGB, icon: "externaldrive", keyboard: .decimalPad, submitLabel: .done)

                HStack(spacing: 10) {
                    Button {
                        applyQuota()
                    } label: {
                        Text(busy ? "设置中…" : "设置")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MD3.onPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(MD3.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)

                    Button {
                        Task { await loadUsers() }
                    } label: {
                        Text("刷新列表")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MD3.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(MD3.primaryContainer)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(MD3.outlineVariant)

                if users.isEmpty {
                    Text("（暂无用户）")
                        .font(.system(size: 13))
                        .foregroundStyle(MD3.onSurfaceVariant)
                } else {
                    VStack(spacing: 8) {
                        ForEach(users) { user in
                            HStack(spacing: 8) {
                                Text(user.username)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(MD3.onSurface)
                                Text(user.tierName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(MD3.onSurfaceVariant)
                                Spacer()
                                Text("\(ByteText.string(user.usedBytes)) / \(ByteText.string(user.quotaBytes))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MD3.onSurfaceVariant)
                                Button {
                                    quotaUser = user.username
                                    quotaGB = String(format: "%g", Double(user.quotaBytes) / 1_073_741_824)
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 13))
                                        .foregroundStyle(MD3.primary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    // MARK: 动作

    private func refreshAll() async {
        await session.refreshProfile()
        if session.me.isAdmin {
            await loadUsers()
        }
    }

    private func loadUsers() async {
        loadingUsers = true
        do {
            users = try await ApiClient.shared.adminUsers()
        } catch {
            users = []
            ToastCentre.shared.show("加载用户列表失败")
        }
        loadingUsers = false
    }

    private func applyQuota() {
        let user = quotaUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = quotaGB.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !text.isEmpty else {
            ToastCentre.shared.show("请输入用户名和空间大小")
            return
        }
        guard let gb = Double(text), gb > 0 else {
            ToastCentre.shared.show("空间大小必须为正数")
            return
        }
        let bytes = Int64(gb * 1024 * 1024 * 1024)
        busy = true
        Task {
            do {
                try await ApiClient.shared.adminSetQuota(username: user, quotaBytes: bytes)
                ToastCentre.shared.show("已设置 \(user) 空间为 \(text) GB")
                await loadUsers()
                await session.refreshProfile()
            } catch {
                ToastCentre.shared.show("设置失败：\(error.localizedDescription)")
            }
            busy = false
        }
    }
}
