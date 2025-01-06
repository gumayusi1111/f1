import Foundation

struct Exercise: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: String
    let description: String
    let notes: String
    var isSystemPreset: Bool
    let unit: String?
    let createdAt: Date
    let updatedAt: Date
    var maxRecord: Double?
    var lastRecord: Double?
    var lastRecordDate: Date?
    
    // 实现 Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Exercise, rhs: Exercise) -> Bool {
        lhs.id == rhs.id
    }
} 