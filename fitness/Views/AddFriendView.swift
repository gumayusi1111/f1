import SwiftUI
import FirebaseFirestore

struct AddFriendView: View {
    @State private var searchText = ""
    @State private var searchResults: [User] = []
    @State private var isSearching = false
    @State private var showError = false
    @State private var errorMessage = ""
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("userName") private var userName: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 搜索框部分
                searchBarSection
                
                // 搜索结果部分
                searchResultsSection
            }
            .padding()
        }
        .navigationTitle("添加好友")
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // 搜索框部分
    private var searchBarSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("输入用户名搜索", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .autocapitalization(.none)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            
            Button(action: performSearch) {
                HStack {
                    Image(systemName: "person.badge.plus")
                    Text("搜索好友")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(searchText.isEmpty ? Color.gray : Color.blue)
                )
                .foregroundColor(.white)
            }
            .disabled(searchText.isEmpty)
        }
    }
    
    // 搜索结果部分
    private var searchResultsSection: some View {
        VStack(spacing: 15) {
            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if searchResults.isEmpty && !searchText.isEmpty {
                emptyResultView
            } else {
                ForEach(searchResults) { user in
                    UserResultCard(user: user, onAdd: {
                        sendFriendRequest(to: user)
                    })
                }
            }
        }
    }
    
    // 空结果视图
    private var emptyResultView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("未找到用户")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("换个用户名试试吧")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        
        let db = Firestore.firestore()
        db.collection("users")
            .whereField("name", isGreaterThanOrEqualTo: searchText)
            .whereField("name", isLessThanOrEqualTo: searchText + "\u{f8ff}")
            .getDocuments(source: .default) { snapshot, error in
                isSearching = false
                
                if let error = error {
                    print("Search error: \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                    showError = true
                    return
                }
                
                // 添加调试打印
                print("Search query: \(searchText)")
                
                searchResults = snapshot?.documents.compactMap { doc -> User? in
                    do {
                        var user = try doc.data(as: User.self)
                        user.id = doc.documentID
                        print("Successfully decoded user: \(user.username) with ID: \(user.id)")
                        return user
                    } catch {
                        print("Error decoding user document \(doc.documentID): \(error)")
                        
                        // 尝试手动创建用户对象
                        let data = doc.data()
                        if let name = data["name"] as? String {
                            return User(
                                id: doc.documentID,
                                username: name,
                                avatar_base64: data["avatar_base64"] as? String,
                                onlineStatus: User.OnlineStatus.offline,
                                lastStatusUpdate: (data["lastStatusUpdate"] as? Timestamp)?.dateValue(),
                                friendIds: data["friendIds"] as? [String] ?? []
                            )
                        }
                        return nil
                    }
                }.filter { $0.id != userId } ?? []
                
                print("Final search results count: \(searchResults.count)")
            }
    }
    
    private func sendFriendRequest(to user: User) {
        print("\n========== 开始发送好友请求 ==========")
        print("从用户: \(userName) (ID: \(userId))")
        print("发送给: \(user.username) (ID: \(user.id))")
        
        let db = Firestore.firestore()
        
        // 1. 检查是否已经是好友
        if user.friendIds.contains(userId) {
            errorMessage = "已经是好友了"
            showError = true
            print("❌ 已经是好友了")
            return
        }
        
        // 2. 检查是否已经发送过请求
        print("📝 检查是否已发送过请求...")
        db.collection("friendRequests")
            .whereField("fromUserId", isEqualTo: userId)
            .whereField("toUserId", isEqualTo: user.id)
            .whereField("status", isEqualTo: FriendRequest.RequestStatus.pending.rawValue)
            .getDocuments(source: .default) { snapshot, error in
                if let error = error {
                    errorMessage = error.localizedDescription
                    showError = true
                    print("❌ 检查请求失败: \(error.localizedDescription)")
                    return
                }
                
                if !(snapshot?.documents.isEmpty ?? true) {
                    errorMessage = "已经发送过请求了"
                    showError = true
                    print("❌ 已经发送过请求了")
                    return
                }
                
                print("✅ 未发现重复请求，继续处理...")
                
                // 3. 创建新的好友请求
                let requestId = UUID().uuidString
                let request = FriendRequest(
                    id: requestId,
                    fromUserId: userId,
                    fromUsername: userName,
                    toUserId: user.id,
                    status: .pending,
                    timestamp: Date()
                )
                
                print("📤 正在保存请求... ID: \(requestId)")
                
                // 4. 保存请求
                let requestData: [String: Any] = [
                    "id": request.id,
                    "fromUserId": request.fromUserId,
                    "fromUsername": request.fromUsername,
                    "toUserId": request.toUserId,
                    "status": request.status.rawValue,
                    "timestamp": Timestamp(date: request.timestamp)
                ]
                
                db.collection("friendRequests")
                    .document(requestId)
                    .setData(requestData) { error in
                        if let error = error {
                            errorMessage = "发送请求失败：\(error.localizedDescription)"
                            showError = true
                            print("❌ 保存请求失败: \(error.localizedDescription)")
                        } else {
                            print("✅ 好友请求发送成功！")
                            // 可以添加成功提示
                            errorMessage = "请求已发送"
                            showError = true
                        }
                    }
            }
        
        print("========== 发送请求流程启动 ==========\n")
    }
}

// 用户结果卡片组件
struct UserResultCard: View {
    let user: User
    let onAdd: () -> Void
    
    var body: some View {
        HStack(spacing: 15) {
            // 头像
            if let avatarData = Data(base64Encoded: user.avatar_base64 ?? ""),
               let uiImage = UIImage(data: avatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.gray)
            }
            
            // 用户信息
            VStack(alignment: .leading, spacing: 4) {
                Text(user.username)
                    .font(.headline)
                
                Text("ID: \(user.id)")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                // 在线状态 - 添加调试信息
                HStack(spacing: 6) {
                    Image(systemName: statusIcon(user.onlineStatus))
                        .foregroundColor(statusColor(user.onlineStatus))
                        .font(.system(size: 12))
                    
                    Text("\(statusText(user.onlineStatus)) (\(user.onlineStatus.rawValue))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .onAppear {
                    print("User online status: \(user.onlineStatus)")
                }
            }
            
            Spacer()
            
            // 添加按钮
            Button(action: onAdd) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.blue))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
    
    // 状态辅助函数
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