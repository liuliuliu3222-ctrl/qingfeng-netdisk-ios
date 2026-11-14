import UIKit
import SwiftUI

/// 切换账号（「我的 → 切换」进入）。
/// 1:1 还原 3.2.0 该页面（对 3.2.0 截图逐像素测量重建）：
/// - iOS insetGrouped 风格：系统分组灰底 + 白色圆角卡片（边距 16pt，圆角 10）
/// - 居中黑色标题「切换账号」（17pt 半粗体，无返回键）
/// - 第一张卡片节标题（灰色 13pt）「已保存的账号」
/// - 行：绿色渐变圆头像 24pt + 绿色用户名 17pt + 当前账号绿色对勾；行高 58pt，行内边距 18pt
/// - 第二张卡片：绿色圆头像 + 绿色「添加新账号」
/// 逻辑：点按账号直接切换；长按账号删除；添加账号确认后退出当前登录回到登录页。
struct AccountSwitchSheet: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var deletingAccount: String?
    @State private var showAddConfirm = false

    // 3.2.0 原版配色（实测）
    private let qfGreen = Color(red: 0.19, green: 0.71, blue: 0.48)       // #30B57A
    private let avatarTop = Color(red: 0.36, green: 0.78, blue: 0.61)
    private let avatarBottom = Color(red: 0.18, green: 0.68, blue: 0.48)  // #2FAE7A

    var body: some View {
        VStack(spacing: 0) {
            // 居中标题（3.2.0 无返回按钮，下滑手势关闭）
            Text("切换账号")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(uiColor: .label))
                .frame(height: 52)
                .frame(maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 节标题（灰色小字，与卡片左缘内缩对齐）
                    Text("已保存的账号")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(uiColor: .systemGray))
                        .padding(.leading, 33)
                        .padding(.bottom, 13)

                    accountCard

                    Spacer(minLength: 0).frame(height: 35)

                    addAccountCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
            Text(account == AppSettings.username
                 ? "这是当前登录的账号，删除后将同时退出登录。"
                 : "将同时删除本机保存的密码；下次使用需重新输入。")
        }
    }

    // MARK: - 账号卡片（白卡圆角10，行高58，绿色头像+绿色用户名+绿色对勾）

    private var accountCard: some View {
        let accounts = session.accountsRevision >= 0 ? AppSettings.savedAccounts : []
        return Group {
            if accounts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color(uiColor: .systemGray))
                    Text("暂无已保存的账号")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(uiColor: .systemGray))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(accounts.enumerated()), id: \.element) { index, account in
                        if index > 0 {
                            Divider()
                                .overlay(Color(uiColor: .separator))
                                .padding(.leading, 52)
                        }
                        accountRow(account, isCurrent: account == AppSettings.username)
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(10)
            }
        }
    }

    private func avatarCircle(_ content: some View) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [avatarTop, avatarBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 24, height: 24)
            content
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
                avatarCircle(Text(String(account.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white))
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
            .padding(.horizontal, 18)
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

    // MARK: - 添加新账号卡片（绿色圆头像 + 绿色文字，同 3.2.0）

    private var addAccountCard: some View {
        Button {
            showAddConfirm = true
        } label: {
            HStack(spacing: 12) {
                avatarCircle(Image(systemName: "person.badge.plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white))
                Text("添加新账号")
                    .font(.system(size: 17))
                    .foregroundStyle(qfGreen)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(10)
    }
}
