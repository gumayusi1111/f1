import Foundation

enum ExerciseType {
    // 主要动作
    static let bench = "卧推"
    static let squat = "深蹲"
    static let deadlift = "硬拉"
    
    // 所有主要动作ID
    static let mainExercises = [bench, squat, deadlift]
    
    // 检查是否是主要动作
    static func isMainExercise(_ exerciseId: String) -> Bool {
        mainExercises.contains(exerciseId)
    }
} 