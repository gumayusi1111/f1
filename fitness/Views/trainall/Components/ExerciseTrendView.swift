import SwiftUI
import Charts

struct ExerciseTrendView: View {
    let stats: TrainingStatsViewModel.ExerciseStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("训练趋势")
                .font(.headline)
            
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
            
            // 最近记录列表
            VStack(alignment: .leading, spacing: 8) {
                Text("最近记录")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ForEach(stats.recentRecords) { record in
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
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
} 