import Foundation
import FirebaseFirestore

struct User: Identifiable, Codable {
    var id: String
    var username: String
    var avatar_base64: String?
    var onlineStatus: OnlineStatus = .offline
    var lastStatusUpdate: Date?
    var friendIds: [String] = []
    var notifications: [Notification]?
    var registerDate: Date? // 注册时间
    var workoutDays: [Date] = [] // 这个属性可以保留但不使用，或者完全移除
    
    // 添加缓存属性
    var cachedWorkoutDays: [Date]?
    var cachedMaxConsecutiveDays: Int?
    var cachedMostFrequentBodyPart: String?
    var cachedMostFrequentWorkoutTime: String?
    var cachedWorkoutTags: [String]?
    var lastCacheUpdate: Date?
    
    // 计算属性
    var totalWorkoutDays: Int {
        Set(workoutDays.map { Calendar.current.startOfDay(for: $0) }).count
    }
    
    var registrationDuration: Int {
        guard let registerDate = registerDate else { return 0 }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: registerDate, to: Date())
        return components.day ?? 0
    }
    
    // 获取本周运动天数
    func getWeeklyWorkouts() -> [Bool] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekDays = (0..<7).map { day in
            calendar.date(byAdding: .day, value: -day, to: today)!
        }.reversed()
        
        return weekDays.map { date in
            workoutDays.contains { calendar.isDate($0, inSameDayAs: date) }
        }
    }
    
    // 添加自定义初始化器
    init(id: String, username: String, avatar_base64: String? = nil, onlineStatus: OnlineStatus = .offline, lastStatusUpdate: Date? = nil, friendIds: [String] = []) {
        self.id = id
        self.username = username
        self.avatar_base64 = avatar_base64
        self.onlineStatus = onlineStatus
        self.lastStatusUpdate = lastStatusUpdate
        self.friendIds = friendIds
    }
    
    enum OnlineStatus: String, Codable {
        case online = "online"
        case away = "away"
        case offline = "offline"
    }
    
    // 自定义初始化器来处理 Firestore 文档
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 尝试解码 id，如果不存在则使用空字符串
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        
        // 解码其他字段
        username = try container.decode(String.self, forKey: .username)
        avatar_base64 = try container.decodeIfPresent(String.self, forKey: .avatar_base64)
        onlineStatus = try container.decodeIfPresent(OnlineStatus.self, forKey: .onlineStatus) ?? .offline
        lastStatusUpdate = try container.decodeIfPresent(Date.self, forKey: .lastStatusUpdate)
        friendIds = try container.decodeIfPresent([String].self, forKey: .friendIds) ?? []
        
        // 解码新增字段
        if let timestamp = try container.decodeIfPresent(Timestamp.self, forKey: .registerDate) {
            registerDate = timestamp.dateValue()
        }
        
        // 解码运动日期数组
        if let timestamps = try container.decodeIfPresent([Timestamp].self, forKey: .workoutDays) {
            workoutDays = timestamps.map { $0.dateValue() }
        } else {
            workoutDays = []
        }
    }
    
    // 编码键
    enum CodingKeys: String, CodingKey {
        case id
        case username = "name"
        case avatar_base64
        case onlineStatus
        case lastStatusUpdate
        case friendIds
        case registerDate = "createdAt"
        case workoutDays
    }
    
    struct Notification: Codable, Identifiable {
        var id: String
        var type: String
        var fromUserId: String
        var timestamp: Date
        var isRead: Bool
    }
    
    // 添加一个异步函数来获取训练日期
    static func fetchWorkoutDays(for userId: String) async throws -> [Date] {
        let db = Firestore.firestore()
        let snapshot = try await db.collection("users").document(userId).collection("trainings").getDocuments()
        
        // 获取所有文档ID (格式为 YYYY-MM-DD)
        return snapshot.documents.compactMap { doc in
            // 将文档ID (YYYY-MM-DD) 转换为 Date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            return dateFormatter.date(from: doc.documentID)
        }
    }
    
    static func ensureCreatedAtField(for userId: String) async {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)
        
        // 检查是否存在 createdAt
        let doc = try? await userRef.getDocument()
        if let data = doc?.data(),
           data["createdAt"] == nil {
            // 如果不存在，设置为当前时间
            try? await userRef.updateData([
                "createdAt": Timestamp(date: Date())
            ])
        }
    }
    
    // 获取最长连续打卡天数
    static func getMaxConsecutiveDays(for userId: String) async throws -> Int {
        let db = Firestore.firestore()
        let snapshot = try await db.collection("users").document(userId)
            .collection("trainings")
            .getDocuments()
        
        // 将所有训练日期转换为 Date 数组并排序
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dates = snapshot.documents.compactMap { doc in
            dateFormatter.date(from: doc.documentID)
        }.sorted()
        
        if dates.isEmpty { return 0 }
        
        var maxStreak = 1
        var currentStreak = 1
        let calendar = Calendar.current
        
        // 计算最长连续天数
        for i in 1..<dates.count {
            let diff = calendar.dateComponents([.day], from: dates[i-1], to: dates[i]).day ?? 0
            if diff == 1 {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 1
            }
        }
        
        return maxStreak
    }
    
    // 获取最常进行的运动类型
    static func getMostFrequentBodyPart(for userId: String) async throws -> String {
        let db = Firestore.firestore()
        let snapshot = try await db.collection("users").document(userId)
            .collection("trainingParts")
            .getDocuments()
        
        // 统计每个部位的出现次数
        var partCounts: [String: Int] = [:]
        for doc in snapshot.documents {
            if let bodyPart = doc.data()["bodyPart"] as? String {
                partCounts[bodyPart, default: 0] += 1
            }
        }
        
        // 找出出现次数最多的部位
        return partCounts.max(by: { $0.value < $1.value })?.key ?? "暂无数据"
    }
    
    // 获取常用运动时段
    static func getMostFrequentWorkoutTime(for userId: String) async throws -> String {
        let db = Firestore.firestore()
        let calendar = Calendar.current
        let today = Date()
        
        // 获取最近7天的日期
        let dates = (0..<7).compactMap { days in
            calendar.date(byAdding: .day, value: -days, to: today)
        }
        
        var allTimes: [Date] = []
        
        // 获取每天的第一条记录时间
        for date in dates {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: date)
            
            // 获取当天的所有记录
            let recordsSnapshot = try await db.collection("users")
                .document(userId)
                .collection("trainings")
                .document(dateString)
                .collection("records")
                .order(by: "createdAt")
                .limit(to: 1)
                .getDocuments()
            
            // 获取第一条记录的时间
            if let firstDoc = recordsSnapshot.documents.first,
               let timestamp = firstDoc.data()["createdAt"] as? Timestamp {
                allTimes.append(timestamp.dateValue())
            }
        }
        
        if allTimes.isEmpty {
            return "暂无数据"
        }
        
        // 计算平均时间
        let components = allTimes.map { date in
            calendar.dateComponents([.hour, .minute], from: date)
        }
        
        let totalMinutes = components.reduce(0) { sum, component in
            sum + (component.hour ?? 0) * 60 + (component.minute ?? 0)
        }
        
        let averageMinutes = totalMinutes / components.count
        let startHour = averageMinutes / 60
        let endHour = (startHour + 2) % 24
        
        // 格式化时间段
        return String(format: "%02d:00-%02d:00", startHour, endHour)
    }
    
    // 添加运动标签计算方法
    static func getWorkoutTags(for userId: String) async throws -> [String] {
        let db = Firestore.firestore()
        let snapshot = try await db.collection("users").document(userId)
            .collection("trainingParts")
            .getDocuments()
        
        // 统计每个部位的出现次数
        var partCounts: [String: Int] = [:]
        for doc in snapshot.documents {
            if let bodyPart = doc.data()["bodyPart"] as? String {
                partCounts[bodyPart, default: 0] += 1
            }
        }
        
        if partCounts.isEmpty {
            return ["新手上路"] // 默认标签
        }
        
        // 计算总训练次数
        let totalCount = partCounts.values.reduce(0, +)
        var tags: [String] = []
        
        // 根据各部位占比添加标签
        for (part, count) in partCounts {
            let percentage = Double(count) / Double(totalCount)
            
            // 根据不同部位和占比添加对应标签
            switch part {
            case "腿部":
                if percentage >= 0.4 {
                    tags.append("腿王")
                } else if percentage >= 0.3 {
                    tags.append("练腿达人")
                }
            case "胸部":
                if percentage >= 0.4 {
                    tags.append("胸肌男神")
                } else if percentage >= 0.3 {
                    tags.append("胸肌达人")
                }
            case "背部":
                if percentage >= 0.4 {
                    tags.append("背肌王者")
                } else if percentage >= 0.3 {
                    tags.append("背肌达人")
                }
            case "肩部":
                if percentage >= 0.4 {
                    tags.append("肩王")
                } else if percentage >= 0.3 {
                    tags.append("肩部达人")
                }
            case "手臂":
                if percentage >= 0.4 {
                    tags.append("手臂王者")
                } else if percentage >= 0.3 {
                    tags.append("手臂达人")
                }
            case "核心":
                if percentage >= 0.4 {
                    tags.append("核心战士")
                } else if percentage >= 0.3 {
                    tags.append("核心达人")
                }
            default:
                break
            }
        }
        
        // 根据总训练次数添加额外标签
        if totalCount >= 100 {
            tags.append("健身狂人")
        } else if totalCount >= 50 {
            tags.append("健身达人")
        } else if totalCount >= 20 {
            tags.append("健身新秀")
        }
        
        return tags.isEmpty ? ["新手上路"] : tags
    }
    
    // 添加缓存更新方法
    mutating func updateCache() async throws {
        cachedWorkoutDays = try await User.fetchWorkoutDays(for: id)
        cachedMaxConsecutiveDays = try await User.getMaxConsecutiveDays(for: id)
        cachedMostFrequentBodyPart = try await User.getMostFrequentBodyPart(for: id)
        cachedMostFrequentWorkoutTime = try await User.getMostFrequentWorkoutTime(for: id)
        cachedWorkoutTags = try await User.getWorkoutTags(for: id)
        lastCacheUpdate = Date()
    }
    
    // 检查缓存是否需要更新
    func needsCacheUpdate() -> Bool {
        guard let lastUpdate = lastCacheUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) > 300 // 5分钟更新一次
    }
}

// 将 FriendRequest 移到单独的结构体
struct FriendRequest: Identifiable, Codable {
    var id: String // Firestore 文档 ID
    let fromUserId: String
    let fromUsername: String
    let toUserId: String
    let status: RequestStatus
    let timestamp: Date
    
    enum RequestStatus: String, Codable {
        case pending = "pending"
        case accepted = "accepted"
        case rejected = "rejected"
    }
} 