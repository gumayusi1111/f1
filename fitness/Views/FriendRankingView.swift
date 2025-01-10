import SwiftUI
import FirebaseFirestore

struct FriendRankingView: View {
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("lastRankingRefreshTime") private var lastRefreshTime: Date = .distantPast
    @State private var friends: [RankedUser] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var selectedCategory = "卧推"
    @State private var showRefreshLimitAlert = false
    
    // 排名类别
    private let categories = ["卧推", "深蹲", "硬拉"]
    
    // 缓存键
    private let RANKING_CACHE_KEY = "friendRankingCache"
    
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
            .padding(.top, 8)
            
            // 类别选择器
            Picker("类别", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                        RankingRow(
                            rank: index + 1,
                            user: friend,
                            category: selectedCategory
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("好友排行")
        .onChange(of: selectedCategory) { _, _ in
            sortFriends()
        }
        .onAppear {
            loadFriendRankings()
        }
        .refreshable {
            await refreshRankings()
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
    
    // 添加缓存相关函数
    private func saveToCache(_ users: [RankedUser]) {
        if let encoded = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(encoded, forKey: RANKING_CACHE_KEY)
            print("✅ 排行榜数据已缓存")
        }
    }
    
    private func loadFromCache() -> [RankedUser]? {
        guard let data = UserDefaults.standard.data(forKey: RANKING_CACHE_KEY),
              let users = try? JSONDecoder().decode([RankedUser].self, from: data) else {
            return nil
        }
        print("✅ 从缓存加载排行榜数据")
        return users
    }
    
    private func loadFriendRankings() {
        print("\n========== 加载好友排行榜 ==========")
        isLoading = true
        
        // 1. 先尝试从缓存加载
        if !isRefreshing, let cachedUsers = loadFromCache() {
            self.friends = cachedUsers
            self.isLoading = false
            print("✅ 使用缓存数据")
            return
        }
        
        let db = Firestore.firestore()
        
        // 1. 获取当前用户的好友列表
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                print("❌ 加载好友列表失败: \(error.localizedDescription)")
                isLoading = false
                return
            }
            
            guard let data = snapshot?.data(),
                  let friendIds = data["friendIds"] as? [String] else {
                print("⚠️ 未找到好友列表")
                isLoading = false
                return
            }
            
            // 确保包含当前用户
            var allUserIds = Set(friendIds)
            allUserIds.insert(userId)
            
            // 2. 加载所有用户信息和他们的运动记录
            let group = DispatchGroup()
            var rankedUsers: [RankedUser] = []
            
            for id in allUserIds {
                group.enter()
                loadUserWithExercises(userId: id) { user in
                    if let user = user {
                        rankedUsers.append(user)
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                self.friends = rankedUsers
                self.sortFriends()
                self.isLoading = false
                self.lastRefreshTime = Date()
                self.saveToCache(rankedUsers)  // 保存到缓存
                print("✅ 排行榜加载完成，共 \(rankedUsers.count) 位好友")
            }
        }
    }
    
    private func loadUserWithExercises(userId: String, completion: @escaping (RankedUser?) -> Void) {
        print("\n========== 开始加载用户 \(userId) 的运动记录 ==========")
        let db = Firestore.firestore()
        
        // 1. 加载用户基本信息
        db.collection("users").document(userId).getDocument { snapshot, error in
            guard let userData = snapshot?.data(),
                  let username = userData["name"] as? String else {
                print("❌ 未找到用户信息")
                completion(nil)
                return
            }
            
            print("✅ 找到用户: \(username)")
            
            let exercisesRef = db.collection("users").document(userId).collection("exercises")
            let group = DispatchGroup()
            var maxRecords: [String: Double] = [:]
            var recordDates: [String: Date] = [:]  // 添加日期记录
            
            // 查找硬拉记录
            group.enter()
            print("\n🔍 开始查询硬拉记录...")
            exercisesRef.document("gxDL9njnomOnyBx37041")
                .collection("records")
                .order(by: "value", descending: true)
                .limit(to: 1)
                .getDocuments { snapshot, error in
                    defer { group.leave() }
                    
                    if let error = error {
                        print("❌ 查询硬拉记录失败: \(error.localizedDescription)")
                        return
                    }
                    
                    if let record = snapshot?.documents.first,
                       let value = record.data()["value"] as? Double,
                       let timestamp = record.data()["date"] as? Timestamp {
                        maxRecords["硬拉"] = value
                        recordDates["硬拉"] = timestamp.dateValue()
                        print("✅ 硬拉最大重量: \(value)kg, 日期: \(timestamp.dateValue())")
                    } else {
                        print("⚠️ 未找到硬拉记录")
                    }
                }
            
            // 查找深蹲记录
            group.enter()
            print("\n🔍 开始查询深蹲记录...")
            exercisesRef.document("PGoi30U9MB4ESHqgm1Ea")
                .collection("records")
                .order(by: "value", descending: true)
                .limit(to: 1)
                .getDocuments { snapshot, error in
                    defer { group.leave() }
                    
                    if let error = error {
                        print("❌ 查询深蹲记录失败: \(error.localizedDescription)")
                        return
                    }
                    
                    if let record = snapshot?.documents.first,
                       let value = record.data()["value"] as? Double,
                       let timestamp = record.data()["date"] as? Timestamp {
                        maxRecords["深蹲"] = value
                        recordDates["深蹲"] = timestamp.dateValue()
                        print("✅ 深蹲最大重量: \(value)kg, 日期: \(timestamp.dateValue())")
                    } else {
                        print("⚠️ 未找到深蹲记录")
                    }
                }
            
            // 查找卧推记录
            group.enter()
            print("\n🔍 开始查询杠铃卧推记录...")
            exercisesRef.document("A26E6B50-474A-4EC3-B6B8-E952391F71D3")
                .collection("records")
                .order(by: "value", descending: true)
                .limit(to: 1)
                .getDocuments { snapshot, error in
                    defer { group.leave() }
                    
                    if let error = error {
                        print("❌ 查询卧推记录失败: \(error.localizedDescription)")
                        return
                    }
                    
                    if let record = snapshot?.documents.first,
                       let value = record.data()["value"] as? Double,
                       let timestamp = record.data()["date"] as? Timestamp {
                        maxRecords["卧推"] = value
                        recordDates["卧推"] = timestamp.dateValue()
                        print("✅ 卧推最大重量: \(value)kg, 日期: \(timestamp.dateValue())")
                    } else {
                        print("⚠️ 未找到卧推记录")
                    }
                }
            
            group.notify(queue: .main) {
                let user = RankedUser(
                    id: userId,
                    username: username,
                    avatar_base64: userData["avatar_base64"] as? String,
                    maxRecords: maxRecords,
                    recordDates: recordDates  // 添加日期
                )
                
                print("\n📊 用户 \(username) 数据加载完成")
                print("记录统计:")
                print("- 深蹲: \(maxRecords["深蹲"] ?? 0)kg")
                print("- 卧推: \(maxRecords["卧推"] ?? 0)kg")
                print("- 硬拉: \(maxRecords["硬拉"] ?? 0)kg")
                
                completion(user)
            }
        }
    }
    
    private func sortFriends() {
        friends.sort { user1, user2 in
            let record1 = user1.maxRecords[selectedCategory] ?? 0
            let record2 = user2.maxRecords[selectedCategory] ?? 0
            return record1 > record2
        }
        
        // 打印排序结果
        print("\n========== \(selectedCategory)排行榜 ==========")
        for (index, user) in friends.enumerated() {
            let record = user.maxRecords[selectedCategory] ?? 0
            print("\(index + 1). \(user.username): \(record)kg")
        }
    }
    
    private func refreshRankings() async {
        if !canRefresh() {
            showRefreshLimitAlert = true
            return
        }
        
        await MainActor.run {
            loadFriendRankings()
        }
    }
}

// 排行榜用户模型
struct RankedUser: Identifiable, Codable {
    let id: String
    let username: String
    let avatar_base64: String?
    let maxRecords: [String: Double]
    let recordDates: [String: Date]
}

// 排行榜行视图
struct RankingRow: View {
    let rank: Int
    let user: RankedUser
    let category: String
    
    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .clear
        }
    }
    
    private var exerciseName: String {
        switch category {
        case "深蹲": return "深蹲"
        case "卧推": return "卧推"
        case "硬拉": return "硬拉"
        default: return category
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                // 排名
                ZStack {
                    Circle()
                        .fill(rankColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .shadow(color: rankColor.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    if rank <= 3 {
                        Image(systemName: "crown.fill")
                            .foregroundColor(rankColor)
                            .font(.system(size: 18))
                            .shadow(color: rankColor.opacity(0.5), radius: 2)
                    } else {
                        Text("\(rank)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                
                // 头像
                if let avatarData = Data(base64Encoded: user.avatar_base64 ?? ""),
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
                
                VStack(alignment: .leading, spacing: 6) {
                    // 用户名
                    Text(user.username)
                        .font(.system(size: 16, weight: .semibold))
                    
                    let record = user.maxRecords[exerciseName] ?? 0
                    if record > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            // 记录值
                            HStack(spacing: 4) {
                                Text("\(record, specifier: "%.1f")")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.blue)
                                Text("kg")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            // 创造时间
                            if let date = user.recordDates[exerciseName] {
                                Text("创造于: \(formatDate(date))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("暂无记录")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 排名指示器
                if user.maxRecords[exerciseName] ?? 0 > 0 {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationView {
        FriendRankingView()
    }
} 