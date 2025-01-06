import Foundation

struct TrainingRecord: Identifiable, Codable {
    let id: String
    let type: String
    let bodyPart: String
    let sets: Int
    let reps: Int
    let weight: Double
    let notes: String
    let date: Date
    let createdAt: Date
    let unit: String?
} 