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
    
    // 每周目标训练频率
    static func weeklyTargetFrequency(_ exerciseId: String) -> Int {
        switch exerciseId {
        case bench: return 2    // 卧推每周2次
        case squat: return 1    // 深蹲每周1次
        case deadlift: return 1 // 硬拉每周1次
        case bigThree: return 4 // 三项总共4次
        default: return 0
        }
    }
    
    // 获取不同周期的目标训练频率
    static func targetFrequency(_ exerciseId: String, period: TrainingStatsViewModel.ComparisonPeriod) -> Int {
        let weeklyTarget = weeklyTargetFrequency(exerciseId)
        
        switch period {
        case .week:
            return weeklyTarget
        case .month:
            return weeklyTarget * 4  // 月度目标 = 周目标 × 4
        case .quarter:
            return weeklyTarget * 13 // 季度目标 = 周目标 × 13
        }
    }
    
    // 获取频率提示信息
    static func getFrequencyMessage(exerciseId: String, currentFrequency: Int, period: TrainingStatsViewModel.ComparisonPeriod) -> (message: String, isAchieved: Bool) {
        let target = targetFrequency(exerciseId, period: period)
        let periodText = period.rawValue
        
        switch exerciseId {
        case bench:
            return currentFrequency >= target
                ? ("本\(periodText)卧推训练已达标 💪", true)
                : ("建议本\(periodText)还需要进行 \(target - currentFrequency) 次卧推训练 🎯", false)
        case squat:
            return currentFrequency >= target
                ? ("本\(periodText)深蹲训练已达标 💪", true)
                : ("建议本\(periodText)还需要进行 \(target - currentFrequency) 次深蹲训练 🎯", false)
        case deadlift:
            return currentFrequency >= target
                ? ("本\(periodText)硬拉训练已达标 💪", true)
                : ("建议本\(periodText)还需要进行 \(target - currentFrequency) 次硬拉训练 🎯", false)
        case bigThree:
            return currentFrequency >= target
                ? ("本\(periodText)三项训练量已达标 💪", true)
                : ("建议本\(periodText)还需要进行 \(target - currentFrequency) 次训练 🎯", false)
        default:
            return ("", false)
        }
    }
} 