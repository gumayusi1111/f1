import SwiftUI

struct TrainingStatsCard: View {
    @StateObject private var viewModel: TrainingStatsViewModel
    
    init(workouts: [WorkoutRecord]) {
        let vm = TrainingStatsViewModel(workouts: workouts)
        _viewModel = StateObject(wrappedValue: vm)
        
        // 延迟设置加载状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            vm.isLoading = false
        }
    }
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                TrainingStatsSkeletonView()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    // 项目选择器
                    MainExerciseSelector(viewModel: viewModel)
                    
                    // 频率分析
                    FrequencySection(viewModel: viewModel, stats: viewModel.frequencyStats)
                    
                    // 当前项目统计
                    ExerciseStatsView(stats: viewModel.selectedExerciseStats)
                    
                    // 训练趋势
                    ExerciseTrendView(stats: viewModel.selectedExerciseStats)
                    
                    // 容量分析
                    VolumeSection(viewModel: viewModel, stats: viewModel.volumeStats)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 5)
            }
        }
        .animation(.default, value: viewModel.isLoading)
    }
}

// 项目统计视图
private struct ExerciseStatsView: View {
    let stats: TrainingStatsViewModel.ExerciseStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 最大重量和当前重量
            HStack(spacing: 20) {
                WeightMetric(
                    title: "最大重量",
                    value: stats.maxWeight,
                    unit: "kg"
                )
                
                WeightMetric(
                    title: "当前重量",
                    value: stats.currentWeight,
                    unit: "kg",
                    progress: stats.progress
                )
            }
            
            // 训练容量
            HStack(spacing: 20) {
                VolumeMetric(
                    title: "周容量",
                    value: stats.weeklyVolume,
                    unit: "kg"
                )
                
                VolumeMetric(
                    title: "月平均",
                    value: stats.weeklyAverageVolume,
                    unit: "kg/周"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// 重量指标
private struct WeightMetric: View {
    let title: String
    let value: Double
    let unit: String
    var progress: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", value))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let progress = progress {
                Text("\(Int(progress))% 维持")
                    .font(.caption)
                    .foregroundColor(progressColor(progress))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func progressColor(_ value: Double) -> Color {
        switch value {
        case 0: return .gray
        case ..<60: return .red
        case 60..<80: return .orange
        case 80..<90: return .blue
        default: return .green
        }
    }
}

// 容量指标
private struct VolumeMetric: View {
    let title: String
    let value: Double
    let unit: String
    
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
} 