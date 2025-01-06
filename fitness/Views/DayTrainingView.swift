import SwiftUI
import FirebaseFirestore

struct DayTrainingView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("todayTrainingPart") private var todayTrainingPart: String = ""
    
    @State private var showingPartSelection = false
    @State private var selectedBodyPart: String
    @State private var showAddTraining = false
    
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    let bodyParts = ["胸部", "背部", "腿部", "肩部", "手臂", "核心"]
    
    // 添加缓存键
    private let trainingPartsCacheKey = "trainingPartsCache"
    
    // 缓存结构
    struct TrainingPartCache: Codable {
        let bodyPart: String
        let date: Date
        let timestamp: Date
        
        var isValid: Bool {
            // 缓存24小时有效
            return Date().timeIntervalSince(timestamp) < 24 * 60 * 60
        }
    }
    
    init(date: Date) {
        self.date = date
        // 初始化选中的训练部位
        _selectedBodyPart = State(initialValue: "")
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 训练部位选择/显示区域
                if selectedBodyPart.isEmpty {
                    // 未设置训练部位时显示选择按钮
                    Button(action: { showingPartSelection = true }) {
                        HStack {
                            Image(systemName: "dumbbell.fill")
                            Text("设置今日训练部位")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                } else {
                    // 已设置训练部位时显示当前部位
                    HStack {
                        Image(systemName: bodyPartIcon(selectedBodyPart))
                            .font(.system(size: 24))
                        Text(selectedBodyPart)
                            .font(.headline)
                        Spacer()
                        Button(action: { showingPartSelection = true }) {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
                
                // 添加训练按钮
                if !selectedBodyPart.isEmpty {
                    Button(action: { showAddTraining = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("添加训练")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(date.formatted(date: .complete, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPartSelection) {
                bodyPartSelectionSheet
            }
            .sheet(isPresented: $showAddTraining) {
                AddTrainingView(date: date) {
                    // 训练添加完成的回调
                }
            }
            .onAppear {
                loadTrainingPart()
            }
            .overlay {
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                        }
                }
                
                if showSuccessAlert {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("设置成功")
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .padding(.bottom, 50)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .alert("设置失败", isPresented: $showErrorAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var bodyPartSelectionSheet: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(bodyParts, id: \.self) { part in
                        Button(action: {
                            // 添加振动反馈
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            
                            selectedBodyPart = part
                            saveTrainingPart(part)
                            showingPartSelection = false
                        }) {
                            VStack(spacing: 12) {
                                Image(systemName: bodyPartIcon(part))
                                    .font(.system(size: 32))
                                    .foregroundColor(selectedBodyPart == part ? .white : .blue)
                                
                                Text(part)
                                    .font(.headline)
                                    .foregroundColor(selectedBodyPart == part ? .white : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(selectedBodyPart == part ? Color.blue : Color.blue.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedBodyPart == part ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .shadow(
                                color: selectedBodyPart == part ? Color.blue.opacity(0.3) : Color.black.opacity(0.05),
                                radius: selectedBodyPart == part ? 8 : 4
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding()
            }
            .navigationTitle("选择训练部位")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") {
                showingPartSelection = false
            })
        }
        .presentationDetents([.medium])
    }
    
    private func bodyPartIcon(_ part: String) -> String {
        switch part {
        case "胸部": return "figure.strengthtraining.traditional"
        case "背部": return "figure.mixed.cardio"
        case "腿部": return "figure.run"
        case "肩部": return "figure.archery"
        case "手臂": return "figure.boxing"
        case "核心": return "figure.core.training"
        default: return "figure.mixed.cardio"
        }
    }
    
    // 加载训练部位时先检查缓存
    private func loadTrainingPart() {
        print("📝 开始加载训练部位")
        
        // 先尝试从缓存加载
        if let cached = loadFromCache() {
            print("✅ 从缓存加载成功: \(cached.bodyPart)")
            selectedBodyPart = cached.bodyPart
            return
        }
        
        print("🔄 缓存未命中,从 Firestore 加载")
        let db = Firestore.firestore()
        db.collection("users")
            .document(userId)
            .collection("trainingParts")
            .document(date.formatDate())
            .getDocument { snapshot, error in
                if let error = error {
                    print("❌ 加载失败: \(error.localizedDescription)")
                    return
                }
                
                if let data = snapshot?.data(),
                   let bodyPart = data["bodyPart"] as? String {
                    print("✅ 从 Firestore 加载成功: \(bodyPart)")
                    selectedBodyPart = bodyPart
                    // 保存到缓存
                    saveToCache(bodyPart: bodyPart)
                } else {
                    print("ℹ️ 未找到训练部位数据")
                }
            }
    }
    
    // 保存到缓存
    private func saveToCache(bodyPart: String) {
        print("💾 保存训练部位到缓存: \(bodyPart)")
        let cache = TrainingPartCache(
            bodyPart: bodyPart,
            date: date,
            timestamp: Date()
        )
        
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: getCacheKey())
            print("✅ 缓存保存成功")
        } else {
            print("❌ 缓存保存失败")
        }
    }
    
    // 从缓存加载
    private func loadFromCache() -> TrainingPartCache? {
        print("📂 尝试从缓存加载训练部位")
        guard let data = UserDefaults.standard.data(forKey: getCacheKey()),
              let cache = try? JSONDecoder().decode(TrainingPartCache.self, from: data),
              cache.isValid else {
            print("ℹ️ 缓存未命中或已过期")
            return nil
        }
        
        print("✅ 缓存命中")
        return cache
    }
    
    // 获取缓存键
    private func getCacheKey() -> String {
        return "\(trainingPartsCacheKey)_\(date.formatDate())_\(userId)"
    }
    
    // 保存训练部位时同时更新缓存
    private func saveTrainingPart(_ part: String) {
        isLoading = true
        print("📝 开始保存训练部位: \(part)")
        
        let db = Firestore.firestore()
        let trainingPartData: [String: Any] = [
            "bodyPart": part,
            "date": date,
            "userId": userId
        ]
        
        db.collection("users")
            .document(userId)
            .collection("trainingParts")
            .document(date.formatDate())
            .setData(trainingPartData) { error in
                isLoading = false
                if let error = error {
                    print("❌ 保存失败: \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                } else {
                    print("✅ 保存成功")
                    // 更新缓存
                    saveToCache(bodyPart: part)
                    
                    withAnimation(.spring(response: 0.3)) {
                        showSuccessAlert = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showSuccessAlert = false
                        }
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