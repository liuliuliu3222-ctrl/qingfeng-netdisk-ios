import UIKit
import SwiftUI

/// 已保存的账号（「我的 → 切换」进入）。
/// 1:1 还原 3.2.0 该页面（像素级测量重建）：
/// - iOS 系统分组灰底 (#F2F2F7) + 白色圆角卡片（圆角 10）
/// - 居中标题「已保存的账号」，下方左侧灰色说明文字
/// - 绿色圆形头像 + 绿色用户名 + 当前账号绿色对勾
/// - 「添加账号」行（绿色 person.badge.plus 图标）
/// 逻辑：点按账号直接切换；长按账号删除；添加账号退出当前登录回到登录页。
struct AccountSwitchSheet: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var deletingAccount: String?
    @State private var showAddConfirm = false

    // 3.2.0 原版配色（实测）
    private let qfGreen = Color(red: 0.19, green: 0.71, blue: 0.48)          // #30B57A 文字绿
    private let avatarTop = Color(red: 0.36, green: 0.78, blue: 0.61)        // 头像渐变亮端
    private let avatarBottom = Color(red: 0.18, green: 0.68, blue: 0.48)     // #2FAE7A
    private let sysBg = Color(uiColor: UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)) // #F2F2F7
    private let sysGray = Color(uiColor: UIColor(red: 0.527, green: 0.527, blue: 0.545, alpha: 1)) // #86878B

    var body: some View {
        VStack(spacing: 0) {
            // 居中标题（3.2.0 无返回按钮，下拉关闭）
            ZStack {
                Text("已保存的账号")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .label))
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("退出后需要重新输入账号密码")
                        .font(.system(size: 13))
                        .foregroundStyle(sysGray)
                        .padding(.horizontal, 2)

                    accountCard

                    addAccountCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 32)
            }
        }
        .background(sysBg.ignoresSafeArea())
        .confirmationDialog("退出当前账号？",
                            isPresented: $showAddConfirm,
                            titleVisibility: .visible) {
            Button("退出后需要重新输入账号密码", role: .destructive) {
                session.logout()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除账号",
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
            Text("退出后需要重新输入账号密码")
        }
    }

    // MARK: - 账号卡片（白色圆角 10，行高 58，绿色头像 + 绿色用户名 + 绿色对勾）

    private var accountCard: some View {
        let accounts = session.accountsRevision >= 0 ? AppSettings.savedAccounts : []
        return Group {
            if accounts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(sysGray)
                    Text("暂无已保存的账号")
                        .font(.system(size: 15))
                        .foregroundStyle(sysGray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(accounts.enumerated()), id: \.element) { index, account in
                        if index > 0 {
                            Divider()
                                .overlay(Color(uiColor: .separator))
                                .padding(.leading, 68)
                        }
                        accountRow(account, isCurrent: account == AppSettings.username)
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(10)
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
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [avatarTop, avatarBottom],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Text(String(account.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(account)
                    .font(.system(size: 17))
                    .foregroundStyle(qfGreen)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(qfGreen)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                deletingAccount = account
            } label: {
                Label("删除账号", systemImage: "trash")
            }
        }
    }

    // MARK: - 添加账号卡片（绿色 person.badge.plus + 绿色文字，同 3.2.0）

    private var addAccountCard: some View {
        Button {
            showAddConfirm = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [avatarTop, avatarBottom],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("添加账号")
                    .font(.system(size: 17))
                    .foregroundStyle(qfGreen)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(10)
    }
}
