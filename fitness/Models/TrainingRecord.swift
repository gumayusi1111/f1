import Foundation
import FirebaseFirestore

struct TrainingRecord: Identifiable, Codable {
    let id: String
    let type: String
    let bodyPart: String
    let sets: Int
    let reps: Int
    let weight: Double
    let notes: String
    let date: Date
    
    init(id: String,
         type: String,
         bodyPart: String,
         sets: Int,
         reps: Int,
         weight: Double,
         notes: String,
         date: Date) {
        self.id = id
        self.type = type
        self.bodyPart = bodyPart
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.notes = notes
        self.date = date
    }
} 