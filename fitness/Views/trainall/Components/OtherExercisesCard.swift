import SwiftUI
import Charts

struct OtherExercisesCard: View {
    let workouts: [WorkoutRecord]
    @State private var selectedExercise: String?
    
    private var otherExercises: [String] {
        let mainExercises = ExerciseType.mainExercises
        return Array(Set(workouts
            .filter { !mainExercises.contains($0.exerciseId) }
            .map { $0.exerciseId }
        )).sorted()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("其他训练动作")
                .font(.headline)
            
            if otherExercises.isEmpty {
                Text("暂无其他训练记录")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                OtherExerciseSelector(
                    exercises: otherExercises,
                    selectedExercise: $selectedExercise,
                    workouts: workouts
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

private struct OtherExerciseSelector: View {
    let exercises: [String]
    @Binding var selectedExercise: String?
    let workouts: [WorkoutRecord]
    
    var body: some View {
        VStack {
            Picker("选择动作", selection: $selectedExercise) {
                Text("选择动作").tag(Optional<String>.none)
                ForEach(exercises, id: \.self) { exercise in
                    Text(exercise).tag(Optional(exercise))
                }
            }
            .pickerStyle(.menu)
            
            if let exerciseId = selectedExercise {
                ExerciseChart(
                    exerciseId: exerciseId,
                    workouts: workouts.filter { $0.exerciseId == exerciseId }
                )
            }
        }
    }
}

private struct ExerciseChart: View {
    let exerciseId: String
    let workouts: [WorkoutRecord]
    
    private var chartData: [(date: Date, weight: Double)] {
        workouts
            .map { (date: $0.date, weight: $0.weight) }
            .sorted { $0.date < $1.date }
    }
    
    var body: some View {
        if chartData.isEmpty {
            Text("暂无训练数据")
                .foregroundColor(.secondary)
                .padding()
        } else {
            Chart {
                ForEach(chartData, id: \.date) { item in
                    LineMark(
                        x: .value("日期", item.date),
                        y: .value("重量", item.weight)
                    )
                    .foregroundStyle(.blue.gradient)
                    
                    PointMark(
                        x: .value("日期", item.date),
                        y: .value("重量", item.weight)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .frame(height: 200)
        }
    }
} 