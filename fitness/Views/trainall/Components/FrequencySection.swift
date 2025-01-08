import SwiftUI

struct FrequencySection: View {
    @ObservedObject var viewModel: TrainingStatsViewModel
    let stats: TrainingStatsViewModel.FrequencyStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("训练频率")
                    .font(.headline)
                
                Spacer()
                
                // 时间段选择器
                Picker("时间段", selection: $viewModel.selectedPeriod) {
                    ForEach(TrainingStatsViewModel.ComparisonPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // 频率对比
            HStack(spacing: 20) {
                FrequencyMetric(
                    title: "本\(stats.period.rawValue)训练",
                    value: stats.current,
                    unit: "次",
                    trend: stats.changePercentage
                )
                
                FrequencyMetric(
                    title: "上\(stats.period.rawValue)训练",
                    value: stats.previous,
                    unit: "次"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

private struct FrequencyMetric: View {
    let title: String
    let value: Int
    let unit: String
    var trend: Double? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(value)")
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