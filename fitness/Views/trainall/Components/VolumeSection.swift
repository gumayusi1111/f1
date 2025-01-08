import SwiftUI

struct VolumeSection: View {
    @ObservedObject var viewModel: TrainingStatsViewModel
    let stats: TrainingStatsViewModel.VolumeStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("训练容量")
                    .font(.headline)
                
                Spacer()
                
                // 时间段选择器
                Picker("时间段", selection: $viewModel.volumePeriod) {
                    ForEach(TrainingStatsViewModel.ComparisonPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // 容量对比
            HStack(spacing: 20) {
                VolumeMetric(
                    title: "本\(stats.period.rawValue)容量",
                    value: stats.current,
                    unit: "kg",
                    trend: stats.changePercentage
                )
                
                VolumeMetric(
                    title: "上\(stats.period.rawValue)容量",
                    value: stats.previous,
                    unit: "kg"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

private struct VolumeMetric: View {
    let title: String
    let value: Double
    let unit: String
    var trend: Double? = nil
    
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
} 