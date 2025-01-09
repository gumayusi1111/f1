import SwiftUI
import FirebaseFirestore

struct FriendDetailView: View {
    let friend: User
    @Environment(\.dismiss) private var dismiss
    @State private var showRemoveAlert = false
    @AppStorage("userId") private var userId: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 头像部分
                avatarSection
                
                // 基本信息部分
                infoSection
                
                // 操作按钮部分
                actionSection
            }
            .padding()
        }
        .navigationTitle("好友详情")
        .alert("确认删除", isPresented: $showRemoveAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                removeFriend()
            }
        } message: {
            Text("确定要删除该好友吗？")
        }
    }
    
    private var avatarSection: some View {
        VStack(spacing: 12) {
            if let avatarData = Data(base64Encoded: friend.avatar_base64 ?? ""),
               let uiImage = UIImage(data: avatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(statusColor(friend.onlineStatus), lineWidth: 3))
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.gray)
            }
            
            Text(friend.username)
                .font(.title2)
                .bold()
        }
    }
    
    private var infoSection: some View {
        VStack(spacing: 16) {
            // 在线状态
            HStack {
                Image(systemName: statusIcon(friend.onlineStatus))
                    .foregroundColor(statusColor(friend.onlineStatus))
                Text(statusText(friend.onlineStatus))
                    .foregroundColor(.secondary)
            }
            
            // 用户 ID
            HStack {
                Text("用户 ID:")
                    .foregroundColor(.secondary)
                Text(friend.id)
                    .font(.system(.body, design: .monospaced))
            }
            
            // 最后更新时间
            if let lastUpdate = friend.lastStatusUpdate {
                HStack {
                    Text("最后更新:")
                        .foregroundColor(.secondary)
                    Text(lastUpdate.formatted())
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
    
    private var actionSection: some View {
        Button(action: {
            showRemoveAlert = true
        }) {
            HStack {
                Image(systemName: "person.badge.minus")
                Text("删除好友")
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
        }
    }
    
    private func removeFriend() {
        let db = Firestore.firestore()
        
        // 1. 从当前用户的好友列表中移除
        db.collection("users").document(userId).updateData([
            "friendIds": FieldValue.arrayRemove([friend.id])
        ])
        
        // 2. 从好友的好友列表中移除当前用户
        db.collection("users").document(friend.id).updateData([
            "friendIds": FieldValue.arrayRemove([userId])
        ]) { error in
            if error == nil {
                // 3. 返回上一页
                dismiss()
            }
        }
    }
    
    private func statusIcon(_ status: User.OnlineStatus) -> String {
        switch status {
        case .online: return "circle.fill"
        case .away: return "moon.fill"
        case .offline: return "circle.slash"
        }
    }
    
    private func statusColor(_ status: User.OnlineStatus) -> Color {
        switch status {
        case .online: return .green
        case .away: return .yellow
        case .offline: return .gray
        }
    }
    
    private func statusText(_ status: User.OnlineStatus) -> String {
        switch status {
        case .online: return "在线"
        case .away: return "离开"
        case .offline: return "离线"
        }
    }
} 