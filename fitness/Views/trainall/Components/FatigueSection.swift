import SwiftUI

struct FatigueSection: View {
    let stats: [TrainingStatsViewModel.FatigueStat]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("疲劳度分析")
                .font(.headline)
            
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
    
    private var statusColor: Color {
        switch stat.fatigueLevel {
        case 0: return .gray
        case ..<60: return .green  // 恢复良好
        case 60..<80: return .blue // 适中
        case 80..<90: return .orange // 较高
        default: return .red // 过度疲劳
        }
    }
    
    private var statusText: String {
        switch stat.fatigueLevel {
        case 0: return "无数据"
        case ..<60: return "恢复良好"
        case 60..<80: return "适中"
        case 80..<90: return "较高"
        default: return "过度疲劳"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stat.name)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(stat.fatigueLevel))%")
                    .font(.headline)
                    .foregroundColor(statusColor)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    
                    Rectangle()
                        .fill(statusColor)
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
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
        }
    }
} 