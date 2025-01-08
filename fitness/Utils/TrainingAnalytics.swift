import Foundation

struct TrainingAnalytics {
    // 计算训练容量
    static func calculateVolume(workouts: [WorkoutRecord], in period: DatePeriod) -> Double {
        let filteredWorkouts = workouts.filter { period.contains($0.date) }
        return filteredWorkouts.reduce(0) { $0 + ($1.weight * Double($1.sets ?? 1)) }
    }
    
    // 计算疲劳度 (基于PR的百分比)
    static func calculateFatigue(currentWeight: Double, pr: Double) -> Double {
        guard pr > 0 else { return 0 }
        return (currentWeight / pr) * 100
    }
    
    // 获取进步曲线数据
    static func getProgressData(workouts: [WorkoutRecord], exerciseId: String) -> [(date: Date, weight: Double)] {
        let filtered = workouts.filter { $0.exerciseId == exerciseId }
            .sorted { $0.date < $1.date }
        
        var maxWeights: [(date: Date, weight: Double)] = []
        var currentMax = 0.0
        
        for workout in filtered {
            if workout.weight > currentMax {
                currentMax = workout.weight
                maxWeights.append((workout.date, workout.weight))
            }
        }
        
        return maxWeights
    }
}

// 时间段枚举
enum DatePeriod {
    case week
    case month
    case quarter
    
    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .week:
            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .quarter:
            let quarterStart = calendar.date(byAdding: .month, value: -3, to: now)!
            return date >= quarterStart && date <= now
        }
    }
} 