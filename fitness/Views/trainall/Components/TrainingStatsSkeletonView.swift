import SwiftUI

struct TrainingStatsSkeletonView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 项目选择器骨架
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonBlock(width: 80, height: 36)
                            .cornerRadius(20)
                    }
                }
                .padding(.horizontal)
            }
            
            // 频率分析骨架
            VStack(spacing: 12) {
                SkeletonBlock(width: 80, height: 24)
                HStack(spacing: 20) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonBlock(height: 60)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // 项目统计骨架
            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    ForEach(0..<2, id: \.self) { _ in
                        SkeletonBlock(height: 80)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // 图表骨架
            VStack(spacing: 12) {
                SkeletonBlock(width: 80, height: 24)
                SkeletonBlock(height: 200)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

private struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 80
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(
                gradient: Gradient(colors: [
                    Color(.systemGray6),
                    Color(.systemGray5),
                    Color(.systemGray6)
                ]),
                startPoint: .leading,
                endPoint: isAnimating ? .trailing : .leading
            ))
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

#Preview {
    TrainingStatsSkeletonView()
} 