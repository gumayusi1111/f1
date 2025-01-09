import SwiftUI
import FirebaseFirestore

struct FriendListView: View {
    @State private var friends: [User] = []
    @State private var isLoading = false
    @AppStorage("userId") private var userId: String = ""
    
    var body: some View {
        List {
            ForEach(friends) { friend in
                HStack {
                    // 头像
                    if let avatarData = Data(base64Encoded: friend.avatar_base64 ?? ""),
                       let uiImage = UIImage(data: avatarData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(friend.username)
                            .font(.headline)
                        
                        Text("ID: \(friend.id)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        // 添加状态指示器
                        HStack(spacing: 6) {
                            // 状态图标
                            Image(systemName: statusIcon(friend.onlineStatus))
                                .foregroundColor(statusColor(friend.onlineStatus))
                                .font(.system(size: 12))
                            
                            // 状态文本
                            Text(statusText(friend.onlineStatus))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        removeFriend(friend)
                    }) {
                        Image(systemName: "person.badge.minus")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("好友列表")
        .onAppear {
            loadFriends()
        }
        .refreshable {
            loadFriends()
        }
        .overlay(Group {
            if isLoading {
                ProgressView()
            }
        })
    }
    
    private func statusColor(_ status: User.OnlineStatus) -> Color {
        switch status {
        case .online:
            return .green
        case .away:
            return .yellow
        case .offline:
            return .gray
        }
    }
    
    private func loadFriends() {
        isLoading = true
        let db = Firestore.firestore()
        
        // 1. 获取当前用户的好友ID列表
        db.collection("users").document(userId).getDocument { snapshot, error in
            guard let data = snapshot?.data(),
                  let friendIds = data["friendIds"] as? [String] else {
                isLoading = false
                return
            }
            
            // 2. 如果没有好友，直接返回
            if friendIds.isEmpty {
                friends = []
                isLoading = false
                return
            }
            
            // 3. 获取所有好友的详细信息
            db.collection("users")
                .whereField(FieldPath.documentID(), in: friendIds)
                .getDocuments { snapshot, error in
                    defer { isLoading = false }
                    
                    if let error = error {
                        print("Error loading friends: \(error)")
                        return
                    }
                    
                    friends = snapshot?.documents.compactMap { doc -> User? in
                        try? doc.data(as: User.self)
                    } ?? []
                }
        }
    }
    
    private func removeFriend(_ friend: User) {
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
                // 3. 更新本地列表
                friends.removeAll { $0.id == friend.id }
            }
        }
    }
    
    private func statusIcon(_ status: User.OnlineStatus) -> String {
        switch status {
        case .online:
            return "circle.fill"
        case .away:
            return "moon.fill"
        case .offline:
            return "circle.slash"
        }
    }
    
    private func statusText(_ status: User.OnlineStatus) -> String {
        switch status {
        case .online:
            return "在线"
        case .away:
            return "离开"
        case .offline:
            return "离线"
        }
    }
} 