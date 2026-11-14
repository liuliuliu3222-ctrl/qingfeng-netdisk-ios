import UIKit
import SwiftUI

/// 切换账号页面（「我的 → 头像旁切换按钮」进入）。
/// - 列表展示本机已保存的账号
/// - 点按账号：直接切换登录（无需重输密码）
/// - 长按账号：弹出「删除该账号」确认（也可点右侧垃圾桶）
/// - 顶部「添加账号」：退出当前登录，回到登录页添加新账号
/// - 删除当前登录账号会同时退出登录
struct AccountSwitchSheet: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var deletingAccount: String?
    @State private var showAddConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(title: "切换账号",
                        subtitle: "点按登录 · 长按删除",
                        showsBack: true,
                        onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 14) {
                    accountListCard
                    hintCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(MD3.background.ignoresSafeArea())
        .confirmationDialog("删除已保存的账号",
                            isPresented: .init(get: { deletingAccount != nil },
                                               set: { if !$0 { deletingAccount = nil } }),
                            titleVisibility: .visible,
                            presenting: deletingAccount) { account in
            Button("删除 \(account)", role: .destructive) {
                withAnimation { session.deleteSavedAccount(account) }
                ToastCentre.shared.show("已删除账号 \(account)")
            }
            Button("取消", role: .cancel) {}
        } message: { account in
            Text(account == AppSettings.username
                 ? "这是当前登录的账号，删除后将同时退出登录。"
                 : "将同时删除本机保存的密码；下次使用需重新输入。")
        }
        .confirmationDialog("添加新账号",
                            isPresented: $showAddConfirm,
                            titleVisibility: .visible) {
            Button("退出当前并去登录") {
                dismiss()
                session.logout()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将退出当前账号并回到登录页，登录新账号后会自动保存在这里。当前账号仍会保留在列表中。")
        }
    }

    // MARK: - 账号列表

    private var accountListCard: some View {
        let accounts = session.accountsRevision >= 0 ? AppSettings.savedAccounts : []
        return MDCard(padding: 0) {
            VStack(spacing: 0) {
                // 添加新账号入口
                Button {
                    showAddConfirm = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(MD3.primary)
                                .frame(width: 40, height: 40)
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(MD3.onPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("添加账号")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(MD3.primary)
                            Text("退出当前，登录新的账号")
                                .font(.system(size: 11))
                                .foregroundStyle(MD3.onSurfaceVariant)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MD3.onSurfaceVariant.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if accounts.isEmpty {
                    Divider().overlay(MD3.outlineVariant)
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 30, weight: .light))
                        Text("还没有已保存的账号")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MD3.onSurfaceVariant)
                        Text("登录成功后会自动记住，之后可在这里一键切换")
                            .font(.system(size: 12))
                            .foregroundStyle(MD3.onSurfaceVariant.opacity(0.8))
                    }
                    .foregroundStyle(MD3.onSurfaceVariant.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ForEach(Array(accounts.enumerated()), id: \.element) { index, account in
                        Divider().overlay(MD3.outlineVariant).padding(.leading, 60)
                        accountRow(account, isCurrent: account == AppSettings.username)
                    }
                }
            }
        }
    }

    private func accountRow(_ account: String, isCurrent: Bool) -> some View {
        HStack(spacing: 14) {
            // 主区域：点按切换
            Button {
                if isCurrent {
                    ToastCentre.shared.show("当前已登录该账号")
                } else {
                    session.switchAccount(to: account)
                    dismiss()
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(isCurrent ? MD3.primary : MD3.primaryContainer)
                            .frame(width: 40, height: 40)
                        Text(String(account.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isCurrent ? MD3.onPrimary : MD3.onPrimaryContainer)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(MD3.onSurface)
                            .lineLimit(1)
                        Text(isCurrent
                             ? "当前登录"
                             : AppSettings.hasPasswordSaved(for: account) ? "已保存密码" : "未保存密码")
                            .font(.system(size: 12))
                            .foregroundStyle(isCurrent ? MD3.primary : MD3.onSurfaceVariant)
                    }
                    Spacer(minLength: 6)
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(MD3.primary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 右侧删除按钮
            Button {
                deletingAccount = account
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MD3.error)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(MD3.errorContainer.opacity(0.5)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除账号 \(account)")
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                deletingAccount = account
            } label: {
                Label("删除该账号", systemImage: "trash")
            }
        }
    }

    // MARK: - 提示

    private var hintCard: some View {
        MDCard(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(MD3.primary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("关于账号管理")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MD3.onSurface)
                    Text("密码仅保存在本机 Keychain，不会上传。删除账号只是移除本机记录，服务器上的文件不受影响。")
                        .font(.system(size: 12))
                        .foregroundStyle(MD3.onSurfaceVariant)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
