import Foundation
import FirebaseFirestore

struct User: Identifiable, Codable {
    var id: String
    var username: String
    var avatar_base64: String?
    var onlineStatus: OnlineStatus = .offline
    var lastStatusUpdate: Date?
    var friendIds: [String] = []
    
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
        
        // 尝试解码 id，如果不存在则使用空字符串（后续会被设置为文档 ID）
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        
        // 解码用户名（从 name 字段）
        username = try container.decode(String.self, forKey: .username)
        
        // 解码可选字段
        avatar_base64 = try container.decodeIfPresent(String.self, forKey: .avatar_base64)
        onlineStatus = try container.decodeIfPresent(OnlineStatus.self, forKey: .onlineStatus) ?? .offline
        lastStatusUpdate = try container.decodeIfPresent(Date.self, forKey: .lastStatusUpdate)
        friendIds = try container.decodeIfPresent([String].self, forKey: .friendIds) ?? []
    }
    
    // 编码键
    enum CodingKeys: String, CodingKey {
        case id
        case username = "name"  // 映射到 Firestore 中的 'name' 字段
        case avatar_base64
        case onlineStatus
        case lastStatusUpdate
        case friendIds
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