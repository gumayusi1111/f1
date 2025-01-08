import Foundation

struct WorkoutRecord: Identifiable, Codable {
    let id: String
    let exerciseId: String
    let weight: Double
    let date: Date
    let sets: Int?
} 