import Foundation

struct WorkoutRecord: Identifiable, Codable {
    var id: String
    var exerciseId: String  // 引用 Exercise 的 id
    var weight: Double
    var date: Date
    var note: String?
    
    // 添加编解码支持
    enum CodingKeys: String, CodingKey {
        case id
        case exerciseId
        case weight
        case date
        case note
    }
} 