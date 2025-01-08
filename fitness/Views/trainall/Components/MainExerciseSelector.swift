import SwiftUI

struct MainExerciseSelector: View {
    @ObservedObject var viewModel: TrainingStatsViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ExerciseType.mainExercises, id: \.self) { exerciseId in
                Button(action: {
                    withAnimation {
                        viewModel.selectedExercise = exerciseId
                    }
                }) {
                    Text(exerciseId)
                        .font(.subheadline)
                        .fontWeight(viewModel.selectedExercise == exerciseId ? .bold : .regular)
                        .foregroundColor(viewModel.selectedExercise == exerciseId ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            viewModel.selectedExercise == exerciseId ? Color.blue : Color.clear
                        )
                }
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
} 