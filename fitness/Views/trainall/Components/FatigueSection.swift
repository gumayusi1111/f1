import SwiftUI

struct FatigueSection: View {
    @ObservedObject var viewModel: TrainingStatsViewModel
    let stats: [TrainingStatsViewModel.FatigueStat]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("疲劳度分析")
                    .font(.headline)
                
                Spacer()
                
                Picker("时间段", selection: $viewModel.fatiguePeriod) {
                    ForEach(TrainingStatsViewModel.ComparisonPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            ForEach(stats, id: \.exerciseId) { stat in
                FatigueBar(stat: stat)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

private struct FatigueBar: View {
    let stat: TrainingStatsViewModel.FatigueStat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stat.name)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(stat.fatigueLevel))%")
                    .font(.headline)
                    .foregroundColor(stat.status.color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    
                    Rectangle()
                        .fill(stat.status.color)
                        .frame(width: geometry.size.width * CGFloat(stat.fatigueLevel / 100), height: 6)
                }
                .cornerRadius(3)
            }
            .frame(height: 6)
            
            HStack {
                Text("\(Int(stat.currentWeight))kg / \(Int(stat.maxWeight))kg")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(stat.suggestion)
                    .font(.caption)
                    .foregroundColor(stat.status.color)
            }
        }
    }
} 