import Foundation

enum ExerciseType {
    // 主要动作
    static let bench = "卧推"
    static let squat = "深蹲"
    static let deadlift = "硬拉"
    static let bigThree = "三项"
    
    // 所有主要动作ID
    static let mainExercises = [bench, squat, deadlift, bigThree]
    
    // 检查是否是主要动作
    static func isMainExercise(_ type: String) -> Bool {
        return [bench, squat, deadlift].contains(type)
    }
} 