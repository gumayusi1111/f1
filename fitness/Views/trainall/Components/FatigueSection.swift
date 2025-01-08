import SwiftUI

struct FatigueSection: View {
    @ObservedObject var viewModel: TrainingStatsViewModel
    let stats: [TrainingStatsViewModel.FatigueStat]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeaderView(viewModel: viewModel)
            StatsList(stats: stats, period: viewModel.fatiguePeriod)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - 子视图
private struct HeaderView: View {
    @ObservedObject var viewModel: TrainingStatsViewModel
    
    var body: some View {
        HStack {
            Text("疲劳度分析")
                .font(.headline)
            
            Spacer()
            
            Picker("周期", selection: $viewModel.fatiguePeriod) {
                ForEach(TrainingStatsViewModel.ComparisonPeriod.allCases, id: \.self) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct StatsList: View {
    let stats: [TrainingStatsViewModel.FatigueStat]
    let period: TrainingStatsViewModel.ComparisonPeriod
    
    var body: some View {
        ForEach(stats, id: \.exerciseId) { stat in
            StatRow(stat: stat, period: period)
        }
    }
}

private struct StatRow: View {
    let stat: TrainingStatsViewModel.FatigueStat
    let period: TrainingStatsViewModel.ComparisonPeriod
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stat.name)
                .font(.subheadline)
            
            FatigueLevelsView(levels: stat.fatigueLevels, period: period)
            
            Text(getSuggestion(for: stat.fatigueLevels))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct FatigueLevelsView: View {
    let levels: [Double]
    let period: TrainingStatsViewModel.ComparisonPeriod
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(levels.enumerated()), id: \.0) { index, level in
                LevelItem(level: level, index: index, period: period)
            }
        }
    }
}

private struct LevelItem: View {
    let level: Double
    let index: Int
    let period: TrainingStatsViewModel.ComparisonPeriod
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(level))%")
                .font(.subheadline)
                .foregroundColor(getFatigueColor(level))
            
            periodLabel
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var periodLabel: some View {
        switch period {
        case .week:
            return Text("Day \(index + 1)")
        case .month:
            return Text("Week \(index + 1)")
        case .quarter:
            return Text("Month \(index + 1)")
        }
    }
}

// MARK: - Helper Functions
private func getFatigueColor(_ level: Double) -> Color {
    switch level {
    case 0: return .gray
    case ..<60: return .green
    case 60..<70: return .blue
    case 70..<80: return .yellow
    case 80..<90: return .orange
    default: return .red
    }
}

private func getSuggestion(for levels: [Double]) -> String {
    let averageLevel = levels.reduce(0, +) / Double(levels.count)
    switch averageLevel {
    case 0: return "开始训练记录吧"
    case ..<60: return "状态良好,可以加大训练强度"
    case 60..<70: return "保持当前训练强度"
    case 70..<80: return "注意控制训练强度"
    case 80..<90: return "建议适当减少重量"
    default: return "需要充分休息恢复"
    }
} 