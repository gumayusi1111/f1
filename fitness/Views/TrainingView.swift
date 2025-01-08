import SwiftUI
import OSLog
import FirebaseFirestore

struct TrainingView: View {
    @StateObject private var viewModel = TrainingViewModel()
    @State private var showingAddTraining = false
    @State private var isRefreshing = false
    @State private var showRefreshHint = true // 控制提示显示
    @State private var isLoading = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 刷新提示
                if showRefreshHint {
                    RefreshHintView()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if !viewModel.workouts.isEmpty {
                    TrainingStatsCard(workouts: viewModel.workouts)
                }
                
                // 训练记录列表
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.workoutsByDate.keys.sorted(by: >), id: \.self) { date in
                        if let dayWorkouts = viewModel.workoutsByDate[date] {
                            TrainingDayRow(date: date, workouts: dayWorkouts)
                        }
                    }
                }
                .padding()
                
                if isLoading {
                    ProgressView()
                }
            }
        }
        .refreshable {
            await viewModel.loadWorkouts()
            
            // 隐藏提示
            withAnimation {
                showRefreshHint = false
            }
        }
        .onAppear {
            Task {
                await viewModel.loadWorkouts()
                
                // 3秒后自动隐藏提示
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showRefreshHint = false
                    }
                }
            }
        }
    }
}

// 刷新提示组件
private struct RefreshHintView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down")
                .rotationEffect(.degrees(isAnimating ? 0 : -10))
                .animation(
                    Animation.easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )
            
            Text("下拉刷新训练数据")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .cornerRadius(20)
        .onAppear {
            isAnimating = true
        }
    }
}

class TrainingViewModel: ObservableObject {
    @Published var workouts: [WorkoutRecord] = []
    @Published var workoutsByDate: [Date: [WorkoutRecord]] = [:]
    private let calendar = Calendar.current
    private let logger = Logger(subsystem: "com.fitness", category: "TrainingViewModel")
    private let db = Firestore.firestore()
    
    func loadWorkouts() async {
        let userId = "I6oLds6wOxxhYmQG2vaD"
        
        logger.info("📊 开始加载训练记录")
        logger.info("- 用户ID: \(userId)")
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("trainings")
                .document("2025-01-07")  // 这里可以改为动态日期
                .collection("records")
                .getDocuments()
            
            let loadedWorkouts = snapshot.documents.compactMap { document -> WorkoutRecord? in
                let data = document.data()
                
                guard let type = data["type"] as? String,
                      let weight = (data["weight"] as? Double) ?? (data["weight"] as? Int).map(Double.init),
                      let date = (data["date"] as? Timestamp)?.dateValue(),
                      let sets = data["sets"] as? Int
                else { return nil }
                
                return WorkoutRecord(
                    id: document.documentID,
                    exerciseId: type,
                    weight: weight,
                    date: date,
                    sets: sets
                )
            }
            
            logger.info("✅ 成功加载 \(loadedWorkouts.count) 条训练记录")
            
            await MainActor.run {
                self.workouts = loadedWorkouts
                self.workoutsByDate = Dictionary(grouping: loadedWorkouts) { workout in
                    self.calendar.startOfDay(for: workout.date)
                }
                
                // 打印加载的记录
                loadedWorkouts.forEach { workout in
                    self.logger.info("  * \(workout.exerciseId): \(workout.weight)kg × \(workout.sets ?? 1)组")
                }
            }
        } catch {
            logger.error("❌ 加载训练记录失败: \(error.localizedDescription)")
            // 应该添加错误状态处理
        }
    }
} 