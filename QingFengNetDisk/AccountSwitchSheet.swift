import UIKit
import SwiftUI

/// 已保存的账号（「我的 → 切换」进入）。
/// 1:1 还原 3.2.0 的二级页面：标题「已保存的账号」+ 纯账号列表。
/// - 点按账号：直接切换登录（无需重输密码）
/// - 长按账号：弹出「删除该账号」确认
/// - 删除当前登录账号会同时退出登录
struct AccountSwitchSheet: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var deletingAccount: String?

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(title: "切换账号",
                        subtitle: "已保存的账号",
                        showsBack: true,
                        onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 14) {
                    accountListCard
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
    }

    // MARK: - 账号列表（3.2.0 原版样式）

    private var accountListCard: some View {
        let accounts = session.accountsRevision >= 0 ? AppSettings.savedAccounts : []
        return MDCard(padding: 0) {
            VStack(spacing: 0) {
                if accounts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(MD3.onSurfaceVariant.opacity(0.6))
                        Text("还没有已保存的账号")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MD3.onSurfaceVariant)
                        Text("登录成功后会自动记住，之后可在这里一键切换")
                            .font(.system(size: 12))
                            .foregroundStyle(MD3.onSurfaceVariant.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ForEach(Array(accounts.enumerated()), id: \.element) { index, account in
                        if index > 0 {
                            Divider().overlay(MD3.outlineVariant).padding(.leading, 60)
                        }
                        accountRow(account, isCurrent: account == AppSettings.username)
                    }
                }
            }
        }
    }

    private func accountRow(_ account: String, isCurrent: Bool) -> some View {
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
            .padding(.horizontal, 16)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                deletingAccount = account
            } label: {
                Label("删除该账号", systemImage: "trash")
            }
        }
    }
}
