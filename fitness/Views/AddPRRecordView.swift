import SwiftUI
import FirebaseFirestore

struct AddPRRecordView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @State private var recordValue: String = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var records: [ExerciseRecord] = [] // 添加历史记录数组
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 历史最佳卡片
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .font(.title2)
                                .foregroundColor(.yellow)
                            Text("历史最佳")
                                .font(.headline)
                            Spacer()
                        }
                        
                        if let maxRecord = exercise.maxRecord {
                            Text("\(maxRecord, specifier: "%.1f") \(exercise.unit ?? "")")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.primary)
                        } else {
                            Text("暂无记录")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // 添加新记录
                    VStack(alignment: .leading, spacing: 16) {
                        Text("添加新记录")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            TextField("输入数值", text: $recordValue)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Text(exercise.unit ?? "")
                                .foregroundColor(.secondary)
                                .frame(width: 40)
                        }
                        
                        Button(action: saveRecord) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("保存中...")
                                } else {
                                    Text("保存记录")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(recordValue.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(recordValue.isEmpty || isLoading)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    .padding(.horizontal)
                    
                    // 历史记录列表
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("历史记录")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        if records.isEmpty {
                            Text("暂无历史记录")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            ForEach(records) { record in
                                RecordRow(record: record)
                            }
                        }
                    }
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarItems(
                leading: Button("取消") { dismiss() }
            )
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadRecords()
            }
        }
    }
    
    private func saveRecord() {
        // TODO: 实现保存记录的逻辑
    }
    
    private func loadRecords() {
        // TODO: 实现加载历史记录的逻辑
    }
}

// 历史记录行视图
struct RecordRow: View {
    let record: ExerciseRecord
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(record.value, specifier: "%.1f")")
                    .font(.system(size: 17, weight: .medium))
                Text(record.date.formatted(.dateTime.month().day().hour().minute()))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if record.isPR {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// 记录数据模型
struct ExerciseRecord: Identifiable {
    let id: String
    let value: Double
    let date: Date
    let isPR: Bool
} 