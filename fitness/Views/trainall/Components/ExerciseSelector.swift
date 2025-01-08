import SwiftUI

struct ExerciseSelector: View {
    @ObservedObject var viewModel: TrainingStatsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForEach(ExerciseType.mainExercises, id: \.self) { exerciseId in
                    ExerciseButton(
                        name: exerciseId,
                        isSelected: viewModel.selectedExercise == exerciseId
                    ) {
                        withAnimation {
                            viewModel.selectedExercise = exerciseId
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct ExerciseButton: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
} 