import SwiftUI
import Charts

struct VolumeSection: View {
    @ObservedObject var viewModel: TrainingStatsViewModel
    let stats: TrainingStatsViewModel.VolumeStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题和时间选择器
            HStack {
                Text("训练容量")
                    .font(.headline)
                Spacer()
                Picker("时间段", selection: $viewModel.volumePeriod) {
                    ForEach(TrainingStatsViewModel.ComparisonPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // 容量指标
            HStack(spacing: 20) {
                VolumeMetric(
                    title: "周容量",
                    value: stats.current,
                    unit: "kg",
                    trend: stats.changePercentage,
                    subtitle: "\(Int(viewModel.selectedExerciseStats.maxWeight))kg 最大"
                )
                
                VolumeMetric(
                    title: "月平均",
                    value: stats.previous,
                    unit: "kg",
                    subtitle: "\(Int(viewModel.selectedExerciseStats.currentWeight))kg 当前"
                )
            }
            
            // 容量对比图表
            VolumeComparisonChart(
                period: viewModel.volumePeriod,
                data: viewModel.volumeComparisonData
            )
            
            // 额外的训练数据分析
            VolumeAnalysis(stats: viewModel.selectedExerciseStats)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// 容量对比图表
struct VolumeComparisonChart: View {
    let period: TrainingStatsViewModel.ComparisonPeriod
    let data: [TrainingStatsViewModel.VolumeData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("容量对比")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if data.isEmpty {
                Text("暂无数据")
                    .foregroundColor(.secondary)
                    .frame(height: 150)
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("日期", item.label),
                        y: .value("容量", item.volume)
                    )
                    .foregroundStyle(Color.blue.gradient)
                }
                .frame(height: 150)
            }
        }
    }
}

// 训练数据分析
struct VolumeAnalysis: View {
    let stats: TrainingStatsViewModel.ExerciseStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("训练分析")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // 这里可以添加更多有用的数据分析
            // 例如: 单次最大容量、平均组数、训练密度等
            Group {
                AnalysisRow(title: "单次最大容量", value: "\(Int(stats.maxVolume))kg")
                AnalysisRow(title: "平均训练组数", value: "\(stats.averageSets)组")
                AnalysisRow(title: "训练频率", value: "\(stats.frequency)次/周")
            }
        }
    }
}

struct AnalysisRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

private struct VolumeMetric: View {
    let title: String
    let value: Double
    let unit: String
    var trend: Double? = nil
    var subtitle: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", value))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let trend = trend {
                HStack(spacing: 4) {
                    Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%.1f%%", abs(trend)))
                }
                .font(.caption)
                .foregroundColor(trend >= 0 ? .green : .red)
            }
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
} 