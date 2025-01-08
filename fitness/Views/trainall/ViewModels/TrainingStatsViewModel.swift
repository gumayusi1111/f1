import Foundation

class TrainingStatsViewModel: ObservableObject {
    @Published private(set) var workouts: [WorkoutRecord]
    @Published var selectedExercise: String = ExerciseType.bench
    @Published var isLoading = true
    private let calendar = Calendar.current
    
    init(workouts: [WorkoutRecord]) {
        self.workouts = workouts
    }
    
    // 获取指定日期范围内的训练记录
    func getWorkouts(from startDate: Date, to endDate: Date) -> [WorkoutRecord] {
        workouts.filter { workout in
            workout.date >= startDate && workout.date <= endDate
        }
    }
    
    // 获取最近N天的训练记录
    func getRecentWorkouts(days: Int) -> [WorkoutRecord] {
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!
        return getWorkouts(from: startDate, to: Date())
    }
    
    // 按日期分组获取训练记录
    func getWorkoutsByDate() -> [Date: [WorkoutRecord]] {
        let calendar = Calendar.current
        return Dictionary(grouping: workouts) { workout in
            calendar.startOfDay(for: workout.date)
        }.mapValues { workouts in
            workouts.sorted { $0.date > $1.date }
        }
    }
    
    // 获取特定动作的训练记录
    func getWorkouts(for exerciseId: String) -> [WorkoutRecord] {
        workouts.filter { $0.exerciseId == exerciseId }
    }
    
    // MARK: - 三大项目数据
    var bigThreeWorkouts: [WorkoutRecord] {
        workouts.filter { ExerciseType.isMainExercise($0.exerciseId) }
    }
    
    // MARK: - 频率分析
    struct FrequencyStats {
        let current: Int
        let previous: Int
        let period: ComparisonPeriod
        
        var changePercentage: Double {
            guard previous > 0 else { return 0 }
            return Double(current - previous) / Double(previous) * 100
        }
        
        var isImproved: Bool {
            current > previous
        }
    }
    
    @Published var frequencyPeriod: ComparisonPeriod = .week
    
    var frequencyStats: FrequencyStats {
        let filteredWorkouts = selectedExercise == ExerciseType.bigThree 
            ? bigThreeWorkouts 
            : workouts.filter { $0.exerciseId == selectedExercise }
            
        let current = filteredWorkouts.filter { 
            isWithinDays($0.date, days: frequencyPeriod.days) 
        }.count
        
        let previous = calculatePreviousFrequency(
            days: frequencyPeriod.days,
            workouts: filteredWorkouts
        )
        
        return FrequencyStats(
            current: current,
            previous: previous,
            period: frequencyPeriod
        )
    }
    
    private func calculatePreviousFrequency(days: Int, workouts: [WorkoutRecord]) -> Int {
        let endDate = calendar.date(byAdding: .day, value: -days, to: Date())!
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!
        
        return workouts
            .filter { $0.date >= startDate && $0.date <= endDate }
            .count
    }
    
    // MARK: - 容量分析
    enum ComparisonPeriod: String, CaseIterable {
        case week = "周"
        case month = "月"
        case quarter = "季度"
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            }
        }
    }
    
    struct VolumeStats {
        let current: Double
        let previous: Double
        let period: ComparisonPeriod
        
        var changePercentage: Double {
            guard previous > 0 else { return 0 }
            return ((current - previous) / previous) * 100
        }
        
        var isImproved: Bool {
            current > previous
        }
    }
    
    @Published var volumePeriod: ComparisonPeriod = .week
    
    var volumeStats: VolumeStats {
        let filteredWorkouts = selectedExercise == ExerciseType.bigThree 
            ? bigThreeWorkouts 
            : workouts.filter { $0.exerciseId == selectedExercise }
            
        let currentPeriod = calculateVolume(
            days: volumePeriod.days,
            workouts: filteredWorkouts
        )
        let previousPeriod = calculateVolumePrevious(
            days: volumePeriod.days,
            workouts: filteredWorkouts
        )
        
        return VolumeStats(
            current: currentPeriod,
            previous: previousPeriod,
            period: volumePeriod
        )
    }
    
    private func calculateVolume(days: Int, workouts: [WorkoutRecord]) -> Double {
        workouts
            .filter { isWithinDays($0.date, days: days) }
            .reduce(0) { sum, workout in
                sum + (workout.weight * Double(workout.sets ?? 1))
            }
    }
    
    private func calculateVolumePrevious(days: Int, workouts: [WorkoutRecord]) -> Double {
        let endDate = calendar.date(byAdding: .day, value: -days, to: Date())!
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!
        
        return workouts
            .filter { $0.date >= startDate && $0.date <= endDate }
            .reduce(0) { sum, workout in
                sum + (workout.weight * Double(workout.sets ?? 1))
            }
    }
    
    // MARK: - 疲劳度分析
    struct FatigueStat {
        let exerciseId: String
        let name: String
        let currentWeight: Double
        let maxWeight: Double
        let fatigueLevel: Double
    }
    
    var fatigueStats: [FatigueStat] {
        ExerciseType.mainExercises.map { exerciseId in
            let exerciseWorkouts = workouts.filter { $0.exerciseId == exerciseId }
            let maxWeight = exerciseWorkouts.map { $0.weight }.max() ?? 0
            let currentWeight = exerciseWorkouts.sorted { $0.date > $1.date }.first?.weight ?? 0
            let fatigueLevel = maxWeight > 0 ? (currentWeight / maxWeight * 100) : 0
            
            return FatigueStat(
                exerciseId: exerciseId,
                name: exerciseId,
                currentWeight: currentWeight,
                maxWeight: maxWeight,
                fatigueLevel: fatigueLevel
            )
        }
    }
    
    // MARK: - Private Helpers
    private func isWithinDays(_ date: Date, days: Int) -> Bool {
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!
        return date >= startDate && date <= Date()
    }
    
    // 获取当前选中运动的训练记录
    var selectedExerciseWorkouts: [WorkoutRecord] {
        if selectedExercise == ExerciseType.bigThree {
            return bigThreeWorkouts // 返回所有三项运动的记录
        }
        return workouts.filter { $0.exerciseId == selectedExercise }
    }
    
    // 获取当前选中动作的统计数据
    var selectedExerciseStats: ExerciseStats {
        let records = selectedExerciseWorkouts.sorted { $0.date > $1.date }
        let maxWeight = records.map { $0.weight }.max() ?? 0
        let currentWeight = records.first?.weight ?? 0
        let weeklyVolume = calculateVolumeForExercise(selectedExercise, days: 7)
        let monthlyVolume = calculateVolumeForExercise(selectedExercise, days: 30)
        
        return ExerciseStats(
            exerciseId: selectedExercise,
            maxWeight: maxWeight,
            currentWeight: currentWeight,
            weeklyVolume: weeklyVolume,
            monthlyVolume: monthlyVolume,
            recentRecords: Array(records.prefix(5))
        )
    }
    
    private func calculateVolumeForExercise(_ exerciseId: String, days: Int) -> Double {
        workouts
            .filter { $0.exerciseId == exerciseId && isWithinDays($0.date, days: days) }
            .reduce(0) { sum, workout in
                sum + (workout.weight * Double(workout.sets ?? 1))
            }
    }
    
    struct ExerciseStats {
        let exerciseId: String
        let maxWeight: Double
        let currentWeight: Double
        let weeklyVolume: Double
        let monthlyVolume: Double
        let recentRecords: [WorkoutRecord]
        
        var progress: Double {
            maxWeight > 0 ? (currentWeight / maxWeight * 100) : 0
        }
        
        var weeklyAverageVolume: Double {
            monthlyVolume / 4
        }
    }
    
    // 获取非三大项的其他训练记录
    var otherWorkouts: [WorkoutRecord] {
        workouts.filter { workout in
            !ExerciseType.isMainExercise(workout.exerciseId)
        }
        .sorted { $0.date > $1.date }  // 按日期降序排序
    }
    
    // 获取其他训练的分组数据
    var otherWorkoutsByType: [String: [WorkoutRecord]] {
        Dictionary(grouping: otherWorkouts) { $0.exerciseId }
    }
} 