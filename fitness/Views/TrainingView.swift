import SwiftUI

struct TrainingView: View {
    @State private var workouts: [WorkoutRecord] = []
    
    var body: some View {
        NavigationView {
            List {
                // 训练记录列表
                Text("训练记录")
            }
            .navigationTitle("训练跟踪")
            .toolbar {
                Button("开始训练") {
                    // 开始新的训练
                }
            }
        }
    }
} 