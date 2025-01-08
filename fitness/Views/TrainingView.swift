import SwiftUI
import OSLog
import FirebaseFirestore

struct TrainingView: View {
    @State private var workouts: [WorkoutRecord] = []
    @State private var selectedChartType: ChartType = .all
    @State private var personalRecords: (bench: Double, squat: Double, deadlift: Double) = (0, 0, 0)
    private let logger = Logger(subsystem: "com.fitness", category: "TrainingView")
    private let db = Firestore.firestore()
    
    // 运动ID常量
    private struct ExerciseIDs {
        static let bench = "B4271D05-0657-4E82-9C99-87FF7E4FC470"  // 卧推
        static let deadlift = "gxDL9njnomOnyBx37041"               // 硬拉
        static let squat = "PGoi30U9MB4ESHqgm1Ea"                 // 深蹲
    }
    
    // 图表类型
    enum ChartType: String, CaseIterable {
        case all = "全部"
        case bench = "卧推"
        case squat = "深蹲"
        case deadlift = "硬拉"
    }
    
    var body: some View {
        NavigationView {
            List {
                // 训练统计卡片
                VStack(spacing: 0) {
                    // 图表类型选择器
                    Picker("图表类型", selection: $selectedChartType) {
                        ForEach(ChartType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    // 训练统计卡片
                    TrainingStatsCard(
                        workouts: selectedChartType == .all ? workouts :
                            workouts.filter { $0.exerciseId == selectedChartType.exerciseId }
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                
                // 训练记录列表
                ForEach(workoutsByDate.keys.sorted(by: >), id: \.self) { date in
                    if let dayWorkouts = workoutsByDate[date] {
                        TrainingDayRow(date: date, workouts: dayWorkouts)
                            .onAppear {
                                // 打印每日训练记录
                                logDailyWorkouts(date: date, workouts: dayWorkouts)
                            }
                    }
                }
            }
            .navigationTitle("训练跟踪")
            .toolbar {
                Button("开始训练") {
                    // 开始新的训练
                }
            }
        }
        .onAppear {
            loadPersonalRecords()
            loadWorkouts()
        }
    }
    
    // 按日期分组的训练记录
    private var workoutsByDate: [Date: [WorkoutRecord]] {
        Dictionary(grouping: workouts) { workout in
            Calendar.current.startOfDay(for: workout.date)
        }
    }
    
    // 打印每日训练记录
    private func logDailyWorkouts(date: Date, workouts: [WorkoutRecord]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        logger.info("📅 \(dateFormatter.string(from: date), privacy: .public) 训练记录:")
        for workout in workouts {
            logger.info("- \(workout.exerciseId, privacy: .public): \(workout.weight, privacy: .public)kg x \(workout.sets ?? 1, privacy: .public)组")
        }
    }
    
    private func loadPersonalRecords() {
        let userId = "I6oLds6wOxxhYmQG2vaD"
        
        // 使用 DispatchGroup 来同步加载
        let group = DispatchGroup()
        var records: [String: Double] = [:]
        
        // 加载卧推记录
        group.enter()
        loadExercisePR(userId: userId, exerciseId: ExerciseIDs.bench) { value in
            records[ExerciseIDs.bench] = value
            group.leave()
        }
        
        // 加载深蹲记录
        group.enter()
        loadExercisePR(userId: userId, exerciseId: ExerciseIDs.squat) { value in
            records[ExerciseIDs.squat] = value
            group.leave()
        }
        
        // 加载硬拉记录
        group.enter()
        loadExercisePR(userId: userId, exerciseId: ExerciseIDs.deadlift) { value in
            records[ExerciseIDs.deadlift] = value
            group.leave()
        }
        
        // 所有记录加载完成后更新UI
        group.notify(queue: .main) {
            self.personalRecords = (
                bench: records[ExerciseIDs.bench] ?? 0,
                squat: records[ExerciseIDs.squat] ?? 0,
                deadlift: records[ExerciseIDs.deadlift] ?? 0
            )
            
            // 打印汇总数据
            logger.info("""
                💪 训练记录汇总:
                ┌──────┬──────────┐
                │ 卧推 │ \(self.personalRecords.bench, privacy: .public)kg │
                │ 深蹲 │ \(self.personalRecords.squat, privacy: .public)kg │
                │ 硬拉 │ \(self.personalRecords.deadlift, privacy: .public)kg │
                └──────┴──────────┘
                """)
        }
    }
    
    private func loadExercisePR(userId: String, exerciseId: String, completion: @escaping (Double) -> Void) {
        let recordsRef = db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exerciseId)
            .collection("records")
        
        logger.info("🔍 加载[\(getExerciseName(for: exerciseId), privacy: .public)]记录")
        
        recordsRef
            .order(by: "date", descending: true)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    logger.error("❌ [\(getExerciseName(for: exerciseId), privacy: .public)]加载失败: \(error.localizedDescription, privacy: .public)")
                    completion(0)
                    return
                }
                
                if let document = snapshot?.documents.first,
                   let value = (document.data()["value"] as? Double) ?? (document.data()["value"] as? Int).map(Double.init) {
                    logger.info("✅ [\(getExerciseName(for: exerciseId), privacy: .public)]: \(value, privacy: .public)kg")
                    completion(value)
                } else {
                    logger.warning("⚠️ [\(getExerciseName(for: exerciseId), privacy: .public)]未找到记录")
                    completion(0)
                }
            }
    }
    
    // 获取运动名称
    private func getExerciseName(for exerciseId: String) -> String {
        switch exerciseId {
        case ExerciseIDs.bench: return "卧推"
        case ExerciseIDs.squat: return "深蹲"
        case ExerciseIDs.deadlift: return "硬拉"
        default: return "未知"
        }
    }
    
    private func loadWorkouts() {
        let userId = "I6oLds6wOxxhYmQG2vaD"
        
        logger.info("📊 开始加载训练记录")
        logger.info("- 用户ID: \(userId, privacy: .public)")
        
        // 加载三大项的最近记录
        loadExerciseRecords(userId: userId, exerciseId: ExerciseIDs.bench)
        loadExerciseRecords(userId: userId, exerciseId: ExerciseIDs.squat)
        loadExerciseRecords(userId: userId, exerciseId: ExerciseIDs.deadlift)
    }
    
    private func loadExerciseRecords(userId: String, exerciseId: String) {
        let recordsRef = db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exerciseId)
            .collection("records")
        
        logger.info("🔍 开始查询训练记录 - 运动ID: \(exerciseId, privacy: .public)")
        
        recordsRef
            .order(by: "date", descending: true)
            .limit(to: 10)
            .getDocuments { snapshot, error in
                if let error = error {
                    logger.error("❌ 加载训练记录失败: \(error.localizedDescription, privacy: .public)")
                    return
                }
                
                logger.info("📄 查询结果:")
                logger.info("- 文档数量: \(snapshot?.documents.count ?? 0, privacy: .public)")
                
                let newWorkouts = snapshot?.documents.compactMap { document -> WorkoutRecord? in
                    let data = document.data()
                    logger.info("- 文档ID: \(document.documentID, privacy: .public)")
                    logger.info("- 原始数据: \(String(describing: data), privacy: .public)")
                    
                    // 处理可能的整数值
                    let value: Double
                    if let doubleValue = data["value"] as? Double {
                        value = doubleValue
                    } else if let intValue = data["value"] as? Int {
                        value = Double(intValue)
                    } else {
                        logger.warning("⚠️ value字段格式错误")
                        return nil
                    }
                    
                    guard let date = (data["date"] as? Timestamp)?.dateValue() else {
                        logger.warning("⚠️ date字段格式错误")
                        return nil
                    }
                    
                    // sets字段可选，默认为1
                    let sets = (data["sets"] as? Int) ?? 1
                    
                    return WorkoutRecord(
                        id: document.documentID,
                        exerciseId: exerciseId,
                        weight: value,
                        date: date,
                        sets: sets
                    )
                } ?? []
                
                logger.info("✅ 成功加载 \(newWorkouts.count, privacy: .public) 条记录")
                
                DispatchQueue.main.async {
                    self.workouts.append(contentsOf: newWorkouts)
                }
            }
    }
}

// MARK: - 辅助扩展
extension TrainingView.ChartType {
    var exerciseId: String {
        switch self {
        case .all: return ""
        case .bench: return TrainingView.ExerciseIDs.bench
        case .squat: return TrainingView.ExerciseIDs.squat
        case .deadlift: return TrainingView.ExerciseIDs.deadlift
        }
    }
} 