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
                // 趋势图表
                if let exerciseId = selectedExercise,
                   let records = workouts[exerciseId]?.sorted(by: { $0.date < $1.date }) {
                    TrendChartView(records: records, exerciseId: exerciseId)
                }
                
                // 记录列表
                RecordListView(
                    workouts: selectedExercise.map { id in
                        [id: workouts[id] ?? []]
                    } ?? workouts
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - 子视图组件
private struct TrendChartView: View {
    let records: [WorkoutRecord]
    let exerciseId: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(exerciseId)趋势")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let maxWeight = records.map({ $0.weight }).max() {
                    Text("最重: \(Int(maxWeight))kg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemBackground))
                        .cornerRadius(4)
                }
            }
            
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

private struct RecordListView: View {
    let workouts: [String: [WorkoutRecord]]
    
    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(workouts.keys.sorted()), id: \.self) { exerciseId in
                if let records = workouts[exerciseId] {
                    ExerciseRecordView(exerciseId: exerciseId, records: records)
                }
            }
        }
    }
}

private struct ExerciseRecordView: View {
    let exerciseId: String
    let records: [WorkoutRecord]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exerciseId)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let maxWeight = records.map({ $0.weight }).max() {
                    Text("最重: \(Int(maxWeight))kg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemBackground))
                        .cornerRadius(4)
                }
            }
            
            ForEach(records.prefix(3)) { record in
                HStack {
                    Text(record.date.formatted(.dateTime.month().day()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(record.weight))kg")
                        .font(.subheadline)
                    
                    if let sets = record.sets {
                        Text("× \(sets)组")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemBackground))
                            .cornerRadius(4)
                    }
                }
            }
            
            if records.count > 3 {
                Text("及其他 \(records.count - 3) 条记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
        }
    }
} 