import SwiftUI
import FirebaseFirestore

struct DayTrainingView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userId") private var userId: String = ""
    
    @State private var records: [TrainingRecord] = []
    @State private var showingAddTraining = false
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView()
                } else if records.isEmpty {
                    emptyStateView
                } else {
                    trainingList
                }
                
                addTrainingButton
            }
            .navigationTitle(date.formatted(.dateTime.month().day().weekday()))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("关闭") { dismiss() })
            .sheet(isPresented: $showingAddTraining) {
                AddTrainingView(date: date) {
                    // 添加完成后刷新记录
                    loadRecords()
                }
            }
            .onAppear {
                loadRecords()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("今天还没有训练记录")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var trainingList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(records) { record in
                    TrainingRecordRow(record: record)
                }
            }
            .padding()
        }
    }
    
    private var addTrainingButton: some View {
        Button(action: { showingAddTraining = true }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("添加训练")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .padding()
    }
    
    private func loadRecords() {
        isLoading = true
        let db = Firestore.firestore()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        db.collection("users")
            .document(userId)
            .collection("trainings")
            .whereField("date", isGreaterThanOrEqualTo: startOfDay)
            .whereField("date", isLessThan: endOfDay)
            .getDocuments { snapshot, error in
                isLoading = false
                if let documents = snapshot?.documents {
                    self.records = documents.compactMap { doc in
                        let data = doc.data()
                        return TrainingRecord(
                            id: doc.documentID,
                            type: data["type"] as? String ?? "",
                            bodyPart: data["bodyPart"] as? String ?? "",
                            sets: data["sets"] as? Int ?? 0,
                            reps: data["reps"] as? Int ?? 0,
                            weight: data["weight"] as? Double ?? 0,
                            notes: data["notes"] as? String ?? "",
                            date: (data["date"] as? Timestamp)?.dateValue() ?? Date()
                        )
                    }
                }
            }
    }
}

// 训练记录行视图
struct TrainingRecordRow: View {
    let record: TrainingRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.type)
                    .font(.headline)
                Spacer()
                Text(record.bodyPart)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(.systemGray6))
                    )
            }
            
            HStack(spacing: 16) {
                Label("\(record.sets)组", systemImage: "number.circle.fill")
                Label("\(record.reps)次", systemImage: "repeat.circle.fill")
                Label("\(Int(record.weight))kg", systemImage: "scalemass.fill")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
} 