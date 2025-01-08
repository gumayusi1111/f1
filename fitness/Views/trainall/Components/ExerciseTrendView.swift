import SwiftUI
import Charts

struct ExerciseTrendView: View {
    let stats: TrainingStatsViewModel.ExerciseStats
    let exerciseId: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("训练趋势")
                .font(.headline)
            
            if exerciseId == ExerciseType.bigThree {
                // 三项运动趋势对比
                BigThreeTrendChart(records: stats.recentRecords)
            } else {
                // 单项运动趋势
                if stats.recentRecords.isEmpty {
                    Text("暂无训练记录")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Chart {
                        ForEach(stats.recentRecords) { record in
                            LineMark(
                                x: .value("日期", record.date),
                                y: .value("重量", record.weight)
                            )
                            .foregroundStyle(Color.blue.gradient)
                            
                            PointMark(
                                x: .value("日期", record.date),
                                y: .value("重量", record.weight)
                            )
                            .foregroundStyle(.blue)
                        }
                    }
                    .frame(height: 200)
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
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let weight = value.as(Double.self) {
                                    Text("\(Int(weight))kg")
                                        .font(.caption2)
                                }
                            }
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

// 三项运动趋势对比图表
private struct BigThreeTrendChart: View {
    let records: [WorkoutRecord]
    
    var body: some View {
        if records.isEmpty {
            Text("暂无训练记录")
                .foregroundColor(.secondary)
                .padding()
        } else {
            Chart {
                ForEach(ExerciseType.mainExercises, id: \.self) { exerciseId in
                    let exerciseRecords = records.filter { $0.exerciseId == exerciseId }
                    ForEach(exerciseRecords) { record in
                        LineMark(
                            x: .value("日期", record.date),
                            y: .value("重量", record.weight)
                        )
                        .foregroundStyle(by: .value("动作", exerciseId))
                        
                        PointMark(
                            x: .value("日期", record.date),
                            y: .value("重量", record.weight)
                        )
                        .foregroundStyle(by: .value("动作", exerciseId))
                    }
                }
            }
            .frame(height: 200)
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
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let weight = value.as(Double.self) {
                            Text("\(Int(weight))kg")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
    }
} 