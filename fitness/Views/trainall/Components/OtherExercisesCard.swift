import SwiftUI
import Charts

struct OtherExercisesCard: View {
    let workouts: [String: [WorkoutRecord]]
    @State private var selectedExercise: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题和选择器
            HStack {
                Text("其他训练记录")
                    .font(.headline)
                
                Spacer()
                
                Menu {
                    Button("全部动作") {
                        selectedExercise = nil
                    }
                    .labelStyle(.titleAndIcon)
                    .imageScale(.medium)
                    
                    Divider()
                    
                    ForEach(Array(workouts.keys.sorted()), id: \.self) { exerciseId in
                        Button(exerciseId) {
                            selectedExercise = exerciseId
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedExercise ?? "选择动作")
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            
            if workouts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无其他训练记录")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                // 只显示趋势图表
                if let exerciseId = selectedExercise,
                   let records = workouts[exerciseId]?.sorted(by: { $0.date < $1.date }) {
                    TrendChartView(records: records, exerciseId: exerciseId)
                } else {
                    // 当没有选择具体动作时，显示所有动作的趋势
                    ForEach(Array(workouts.keys.sorted()), id: \.self) { exerciseId in
                        if let records = workouts[exerciseId]?.sorted(by: { $0.date < $1.date }) {
                            TrendChartView(records: records, exerciseId: exerciseId)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - 趋势图表组件
private struct TrendChartView: View {
    let records: [WorkoutRecord]
    let exerciseId: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(records) { record in
                    LineMark(
                        x: .value("日期", record.date),
                        y: .value("重量", record.weight)
                    )
                    .foregroundStyle(.blue.gradient)
                    
                    PointMark(
                        x: .value("日期", record.date),
                        y: .value("重量", record.weight)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .frame(height: 150)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date.formatted(.dateTime.month().day()))
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
} 