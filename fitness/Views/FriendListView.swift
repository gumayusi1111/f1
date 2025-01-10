import SwiftUI
import FirebaseFirestore

struct FriendListView: View {
    @State private var friends: [User] = []
    @State private var isLoading = false
    @State private var selectedFriend: User? = nil
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("lastFriendsRefreshTime") private var lastRefreshTime: Date = .distantPast
    @State private var showRefreshLimitAlert = false
    @State private var isRefreshing = false
    @State private var isFirstLoading = true
    
    // 缓存键
    private let FRIENDS_CACHE_KEY = "friendsListCache"
    
    var body: some View {
        VStack(spacing: 0) {
            // 上次刷新时间
            HStack {
                Text("上次更新: \(formatLastRefreshTime())")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            
            if isFirstLoading {
                // 骨架屏加载状态
                VStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in
                        FriendRowSkeleton()
                            .padding(.horizontal)
                    }
                }
            } else if friends.isEmpty {
                // 空状态视图
                VStack(spacing: 16) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("暂无好友")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("去添加一些好友吧")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 好友列表
                List {
                    ForEach(friends) { friend in
                        FriendRow(friend: friend, onTapFriend: {
                            showFriendDetails(friend)
                        })
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("好友列表")
        .sheet(item: $selectedFriend) { friend in
            NavigationView {
                FriendDetailView(friend: friend)
            }
        }
        .onAppear {
            loadFriends()
        }
        .refreshable {
            await refreshFriends()
        }
        .alert("刷新限制", isPresented: $showRefreshLimitAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("请等待一分钟后再次刷新")
        }
    }
    
    // 检查是否可以刷新
    private func canRefresh() -> Bool {
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTime)
        return timeSinceLastRefresh >= 60 // 60秒限制
    }
    
    // 格式化上次刷新时间
    private func formatLastRefreshTime() -> String {
        if lastRefreshTime == .distantPast {
            return "未刷新"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastRefreshTime, relativeTo: Date())
    }
    
    // 缓存相关函数
    private func saveToCache(_ users: [User]) {
        if let encoded = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(encoded, forKey: FRIENDS_CACHE_KEY)
            print("✅ 好友列表已缓存")
        }
    }
    
    private func loadFromCache() -> [User]? {
        guard let data = UserDefaults.standard.data(forKey: FRIENDS_CACHE_KEY),
              let users = try? JSONDecoder().decode([User].self, from: data) else {
            return nil
        }
        print("✅ 从缓存加载好友列表")
        return users
    }
    
    private func loadFriends(forceRefresh: Bool = false) {
        print("\n========== 加载好友列表 ==========")
        
        // 只有在非强制刷新时才使用缓存
        if !forceRefresh, !isRefreshing, let cachedFriends = loadFromCache() {
            self.friends = cachedFriends
            self.isFirstLoading = false
            print("✅ 使用缓存数据")
            return
        }
        
        let db = Firestore.firestore()
        
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                print("❌ 加载好友列表失败: \(error.localizedDescription)")
                isLoading = false
                return
            }
            
            if let data = snapshot?.data(),
               let friendIds = data["friendIds"] as? [String] {
                loadFriendDetails(friendIds)
            } else {
                isLoading = false
            }
        }
    }
    
    private func refreshFriends() async {
        // 显示刷新动画
        isRefreshing = true
        
        if !canRefresh() {
            // 如果在一分钟内，只显示动画
            print("⚠️ 刷新太频繁，使用缓存数据")
            // 短暂延迟以显示刷新动画
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            isRefreshing = false
            showRefreshLimitAlert = true
            return
        }
        
        // 超过一分钟，从数据库同步
        print("\n🔄 开始同步好友列表数据...")
        await MainActor.run {
            isRefreshing = true
            // 强制从数据库加载新数据
            loadFriends(forceRefresh: true)
        }
    }
    
    private func showFriendDetails(_ friend: User) {
        selectedFriend = friend
    }
    
    private func loadFriendDetails(_ friendIds: [String]) {
        print("\n开始加载好友详细信息...")
        print("好友ID列表: \(friendIds)")
        
        let db = Firestore.firestore()
        let group = DispatchGroup()
        var loadedFriends: [User] = []
        
        for friendId in friendIds {
            group.enter()
            print("正在加载好友ID: \(friendId)")
            
            db.collection("users").document(friendId).getDocument { snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    print("❌ 加载好友信息失败: \(error.localizedDescription)")
                    return
                }
                
                do {
                    if var friend = try snapshot?.data(as: User.self) {
                        friend.id = snapshot?.documentID ?? ""
                        print("✅ 成功加载好友: \(friend.username), ID: \(friend.id)")
                        loadedFriends.append(friend)
                    }
                } catch {
                    print("❌ 解码失败: \(error.localizedDescription)")
                    
                    // 尝试手动创建用户对象
                    if let data = snapshot?.data(),
                       let name = data["name"] as? String {
                        let friend = User(
                            id: snapshot?.documentID ?? "",
                            username: name,
                            avatar_base64: data["avatar_base64"] as? String,
                            onlineStatus: .offline,
                            lastStatusUpdate: (data["lastStatusUpdate"] as? Timestamp)?.dateValue(),
                            friendIds: data["friendIds"] as? [String] ?? []
                        )
                        print("✅ 手动创建好友: \(friend.username), ID: \(friend.id)")
                        loadedFriends.append(friend)
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            self.friends = loadedFriends
            self.isLoading = false
            self.isRefreshing = false
            self.isFirstLoading = false
            self.lastRefreshTime = Date()
            self.saveToCache(loadedFriends)
            print("\n最终加载结果:")
            print("- 成功加载好友数量: \(friends.count)")
            print("📅 更新最后刷新时间: \(self.formatLastRefreshTime())")
            friends.forEach { friend in
                print("- 好友: \(friend.username), ID: \(friend.id)")
            }
        }
    }
}

// 好友行视图
struct FriendRow: View {
    let friend: User
    let onTapFriend: () -> Void
    @State private var isReminding = false
    @State private var showReminderAlert = false
    @State private var reminderMessage = ""
    @State private var lastReminderTimes: [String: TimeInterval] = [:]
    
    // 在 onAppear 时加载保存的时间
    private func loadSavedTimes() {
        if let data = UserDefaults.standard.data(forKey: "lastReminderTime"),
           let times = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            lastReminderTimes = times
        }
    }
    
    // 保存时间到 UserDefaults
    private func saveTimes() {
        if let data = try? JSONEncoder().encode(lastReminderTimes) {
            UserDefaults.standard.set(data, forKey: "lastReminderTime")
        }
    }
    
    var body: some View {
        HStack(spacing: 15) {
            // 左侧内容区域（头像和信息）
            Group {
                // 头像
                if let avatarData = Data(base64Encoded: friend.avatar_base64 ?? ""),
                   let uiImage = UIImage(data: avatarData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.gray.opacity(0.3))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.username)
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("ID: \(friend.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // 在线状态
                    HStack(spacing: 6) {
                        Circle()
                            .fill(friend.onlineStatus == .online ? Color.green : 
                                 friend.onlineStatus == .away ? Color.yellow : Color.gray)
                            .frame(width: 8, height: 8)
                        
                        Text(statusText(friend.onlineStatus))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .onTapGesture {
                onTapFriend()
            }
            
            // 右侧按钮区域
            HStack(spacing: 8) {
                // 催促训练按钮
                Button(action: {
                    handleWorkoutReminder()
                }) {
                    Image(systemName: isReminding ? "bell.fill" : "bell")
                        .foregroundColor(isReminding ? .orange : .gray)
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                }
                .disabled(isReminding)
                .alert("提醒", isPresented: $showReminderAlert) {
                    Button("确定", role: .cancel) { }
                } message: {
                    Text(reminderMessage)
                }
                
                // 箭头指示器
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.system(size: 14))
                    .frame(width: 20)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            loadSavedTimes()
        }
    }
    
    private func statusText(_ status: User.OnlineStatus) -> String {
        switch status {
        case .online: return "在线"
        case .away: return "离开"
        case .offline: return "离线"
        }
    }
    
    private func handleWorkoutReminder() {
        // 检查发送频率限制
        if let lastTime = lastReminderTimes[friend.id] {
            let timeInterval = Date().timeIntervalSince1970 - lastTime
            if timeInterval < 24 * 60 * 60 { // 24小时内
                reminderMessage = "今天已经提醒过了,明天再来吧"
                showReminderAlert = true
                return
            }
        }
        
        // 发送提醒
        sendWorkoutReminder()
        
        // 添加震动反馈
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 更新最后提醒时间
        lastReminderTimes[friend.id] = Date().timeIntervalSince1970
        saveTimes() // 保存到 UserDefaults
        
        // 显示成功提示
        reminderMessage = "已发送训练提醒"
        showReminderAlert = true
    }
    
    private func sendWorkoutReminder() {
        withAnimation {
            isReminding = true
        }
        
        let db = Firestore.firestore()
        let notification: [String: Any] = [
            "type": "workout_reminder",
            "fromUserId": UserDefaults.standard.string(forKey: "userId") ?? "",
            "timestamp": Timestamp(),
            "isRead": false,
            "message": "该去运动啦!" // 可以添加自定义消息
        ]
        
        db.collection("users").document(friend.id)
            .collection("notifications").addDocument(data: notification) { error in
                if error == nil {
                    print("✅ 成功发送训练提醒")
                    
                    // 3秒后重置按钮状态
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            isReminding = false
                        }
                    }
                } else {
                    // 发送失败处理
                    reminderMessage = "发送失败,请稍后重试"
                    showReminderAlert = true
                    withAnimation {
                        isReminding = false
                    }
                }
            }
    }
}

// 添加骨架屏组件
struct FriendRowSkeleton: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 15) {
            // 头像骨架
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
            
            // 信息骨架
            VStack(alignment: .leading, spacing: 8) {
                // 用户名骨架
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 16)
                
                // ID骨架
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 12)
                
                // 状态骨架
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 8, height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 12)
                }
            }
            
            Spacer()
            
            // 箭头骨架
            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.2))
        }
        .padding(.vertical, 8)
        .opacity(isAnimating ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
} 