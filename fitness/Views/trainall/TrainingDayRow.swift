import SwiftUI

struct TrainingDayRow: View {
    let date: Date
    let workouts: [WorkoutRecord]
    
    // 计算当天的最大重量
    private var maxLifts: (bench: Double, squat: Double, deadlift: Double) {
        var bench = 0.0
        var squat = 0.0
        var deadlift = 0.0
        
        for workout in workouts {
            switch workout.exerciseId {
            case "bench": bench = max(bench, workout.weight)
            case "squat": squat = max(squat, workout.weight)
            case "deadlift": deadlift = max(deadlift, workout.weight)
            default: break
            }
        }
        
        return (bench, squat, deadlift)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 日期
            Text(date.formatted(.dateTime.day().month()))
                .font(.headline)
            
            // 三大项最大重量
            HStack(spacing: 12) {
                LiftStatView(name: "卧推", weight: maxLifts.bench)
                LiftStatView(name: "深蹲", weight: maxLifts.squat)
                LiftStatView(name: "硬拉", weight: maxLifts.deadlift)
            }
            
            // 训练总数
            Text("训练项目: \(workouts.count)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// 展示单个举重项目的组件
private struct LiftStatView: View {
    let name: String
    let weight: Double
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(Int(weight))kg")
                .font(.system(.body, design: .rounded))
                .bold()
        }
    }
} 