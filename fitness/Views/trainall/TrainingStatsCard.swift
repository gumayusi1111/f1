import SwiftUI
import Charts

struct TrainingStatsCard: View {
    let workouts: [WorkoutRecord]
    
    private var weeklyVolume: Double {
        TrainingAnalytics.calculateVolume(workouts: workouts, in: .week)
    }
    
    private var monthlyVolume: Double {
        TrainingAnalytics.calculateVolume(workouts: workouts, in: .month)
    }
    
    private var quarterlyVolume: Double {
        TrainingAnalytics.calculateVolume(workouts: workouts, in: .quarter)
    }
    
    private var prs: (bench: Double, squat: Double, deadlift: Double) {
        let benchPR = workouts.filter { $0.exerciseId == "bench" }.map { $0.weight }.max() ?? 0
        let squatPR = workouts.filter { $0.exerciseId == "squat" }.map { $0.weight }.max() ?? 0
        let deadliftPR = workouts.filter { $0.exerciseId == "deadlift" }.map { $0.weight }.max() ?? 0
        return (benchPR, squatPR, deadliftPR)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            volumeStatsSection
            fatigueSection
            progressSection
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private var volumeStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("训练容量统计")
                .font(.headline)
            
            HStack(spacing: 16) {
                volumeStatItem(title: "本周", value: weeklyVolume)
                volumeStatItem(title: "本月", value: monthlyVolume)
                volumeStatItem(title: "本季", value: quarterlyVolume)
            }
        }
    }
    
    private var fatigueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("疲劳度指示")
                .font(.headline)
            
            HStack(spacing: 16) {
                fatigueBar(name: "卧推", current: workouts.last { $0.exerciseId == "bench" }?.weight ?? 0, pr: prs.bench)
                fatigueBar(name: "深蹲", current: workouts.last { $0.exerciseId == "squat" }?.weight ?? 0, pr: prs.squat)
                fatigueBar(name: "硬拉", current: workouts.last { $0.exerciseId == "deadlift" }?.weight ?? 0, pr: prs.deadlift)
            }
        }
    }
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("进步曲线")
                .font(.headline)
            
            Chart {
                ForEach(["bench", "squat", "deadlift"], id: \.self) { exerciseId in
                    let progressData = TrainingAnalytics.getProgressData(workouts: workouts, exerciseId: exerciseId)
                    ForEach(progressData, id: \.date) { item in
                        LineMark(
                            x: .value("Date", item.date),
                            y: .value("Weight", item.weight)
                        )
                        .foregroundStyle(by: .value("Exercise", exerciseId))
                    }
                }
            }
            .frame(height: 200)
        }
    }
    
    private func volumeStatItem(title: String, value: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(Int(value))kg")
                .font(.system(.body, design: .rounded))
                .bold()
        }
    }
    
    private func fatigueBar(name: String, current: Double, pr: Double) -> some View {
        let percentage = TrainingAnalytics.calculateFatigue(currentWeight: current, pr: pr)
        
        return VStack(alignment: .leading) {
            Text(name)
                .font(.caption)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                    
                    Rectangle()
                        .fill(fatigueColor(for: percentage))
                        .frame(width: geometry.size.width * percentage / 100)
                }
            }
            .frame(height: 8)
            .cornerRadius(4)
            
            Text("\(Int(percentage))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func fatigueColor(for percentage: Double) -> Color {
        switch percentage {
        case 0..<60: return .green
        case 60..<80: return .yellow
        default: return .red
        }
    }
} 