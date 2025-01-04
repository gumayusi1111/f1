import Foundation

struct User: Identifiable, Codable {
    let id: String
    let name: String
    
    static let samples = [
        User(id: "1", name: "大赵"),
        User(id: "2", name: "大月")
    ]
} 