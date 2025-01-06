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
    
    @State private var showingDeleteAlert = false
    @State private var selectedRecord: TrainingRecord? = nil
    @State private var trainings: [TrainingRecord] = []
    
    @State private var showDeleteSuccess = false
    @State private var deletedRecordName = ""
    
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
                
                // 训练记录列表
                if !trainings.isEmpty {
                    List {
                        ForEach(trainings) { record in
                            TrainingRecordRow(record: record)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        selectedRecord = record
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .padding(.vertical)
                } else if !selectedBodyPart.isEmpty {
                    // 显示空状态
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("今日暂无训练记录")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("点击上方按钮开始添加")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
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
                loadTrainings()
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
                
                if showDeleteSuccess {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(deletedRecordName) 已删除")
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
            .alert("确认删除", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    if let record = selectedRecord {
                        deleteTraining(record)
                    }
                }
            } message: {
                Text(selectedRecord?.type != nil ? "确定要删除「\(selectedRecord!.type)」的训练记录吗？" : "")
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
    
    private func deleteTraining(_ record: TrainingRecord) {
        isLoading = true
        let db = Firestore.firestore()
        deletedRecordName = record.type
        
        db.collection("users")
            .document(userId)
            .collection("trainings")
            .document(record.id)
            .delete { error in
                isLoading = false
                
                if let error = error {
                    errorMessage = "删除失败: \(error.localizedDescription)"
                    showErrorAlert = true
                } else {
                    if let index = trainings.firstIndex(where: { $0.id == record.id }) {
                        trainings.remove(at: index)
                    }
                    showDeleteSuccess = true
                    
                    // 播放触觉反馈
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    
                    // 2秒后隐藏成功提示
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showDeleteSuccess = false
                    }
                }
            }
    }
    
    // 添加加载训练记录的函数
    private func loadTrainings() {
        let db = Firestore.firestore()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        print("\n========== 开始加载训练记录 ==========")
        print("📅 查询日期范围:")
        print("开始时间: \(startOfDay)")
        print("结束时间: \(endOfDay)")
        
        db.collection("users")
            .document(userId)
            .collection("trainings")
            .whereField("date", isGreaterThanOrEqualTo: startOfDay)
            .whereField("date", isLessThan: endOfDay)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ 加载失败: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("⚠️ 没有找到文档")
                    return
                }
                
                print("\n🔍 解析训练记录 (\(documents.count) 条):")
                
                self.trainings = documents.compactMap { doc in
                    let data = doc.data()
                    
                    print("\n📝 记录 ID: \(doc.documentID)")
                    print("原始数据:")
                    data.forEach { key, value in
                        print("- \(key): \(value)")
                    }
                    
                    // 特别检查时间字段
                    if let timestamp = data["date"] as? Timestamp {
                        let date = timestamp.dateValue()
                        print("时间戳解析:")
                        print("- Timestamp: \(timestamp)")
                        print("- 转换后日期: \(date)")
                        print("- 格式化时间: \(date.formatted(.dateTime.hour().minute()))")
                    } else {
                        print("⚠️ 时间字段缺失或格式错误")
                    }
                    
                    // 获取 createdAt，如果已存在就使用原有的，否则使用当前时间
                    let createdAt: Date
                    if let timestamp = data["createdAt"] as? Timestamp {
                        createdAt = timestamp.dateValue()
                    } else if let existingRecord = self.trainings.first(where: { $0.id == doc.documentID }) {
                        // 如果是已存在的记录，保留原有的 createdAt
                        createdAt = existingRecord.createdAt
                    } else {
                        // 新记录使用当前时间
                        createdAt = Date()
                    }
                    
                    return TrainingRecord(
                        id: doc.documentID,
                        type: data["type"] as? String ?? "",
                        bodyPart: data["bodyPart"] as? String ?? "",
                        sets: data["sets"] as? Int ?? 0,
                        reps: data["reps"] as? Int ?? 0,
                        weight: data["weight"] as? Double ?? 0,
                        notes: data["notes"] as? String ?? "",
                        date: (data["date"] as? Timestamp)?.dateValue() ?? Date(),
                        createdAt: createdAt
                    )
                }
                
                print("\n✅ 成功加载 \(self.trainings.count) 条训练记录")
                print("========== 加载完成 ==========\n")
            }
    }
}

// 训练记录行视图
struct TrainingRecordRow: View {
    let record: TrainingRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶部：训练类型和部位标签
            HStack {
                Text(record.type)
                    .font(.system(size: 17, weight: .semibold))
                
                Spacer()
                
                Text(record.bodyPart)
                    .font(.system(size: 13))
                    .foregroundColor(getCategoryColor(record.bodyPart))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(getCategoryColor(record.bodyPart).opacity(0.1))
                    .cornerRadius(6)
            }
            
            // 中间：训练数据
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "number.circle.fill")
                        .foregroundColor(.blue)
                    Text("\(record.sets)组 × \(record.reps)次")
                }
                .font(.system(size: 15))
                
                HStack(spacing: 4) {
                    Image(systemName: "scalemass.fill")
                        .foregroundColor(.blue)
                    Text(String(format: "%.1f kg", record.weight))
                }
                .font(.system(size: 15))
            }
            
            // 底部：备注和时间
            HStack {
                if !record.notes.isEmpty {
                    Text(record.notes)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text(record.createdAt, style: .time)
                }
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
        .padding(.vertical, 4)
        .onAppear {
            print("\n⏰ 训练记录时间显示:")
            print("记录 ID: \(record.id)")
            print("原始日期: \(record.date)")
            print("格式化时间: \(record.date.formatted(.dateTime.hour().minute()))")
            print("时间戳: \(record.date.timeIntervalSince1970)")
        }
    }
    
    // 获取类别颜色
    private func getCategoryColor(_ category: String) -> Color {
        switch category {
        case "胸部": return .red
        case "背部": return .blue
        case "腿部": return .purple
        case "肩部": return .orange
        case "手臂": return .green
        case "核心": return .pink
        default: return .blue
        }
    }
}

// 1. 首先添加一个 SwipeView 组件
struct SwipeView<Content: View>: View {
    let content: Content
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    
    init(@ViewBuilder content: () -> Content, onDelete: @escaping () -> Void) {
        self.content = content()
        self.onDelete = onDelete
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .foregroundColor(.white)
                    .frame(width: 60, height: 50)
            }
            .frame(width: 60, height: 50)
            .background(Color.red)
            .cornerRadius(12)
            
            // 内容视图
            content
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            withAnimation {
                                if value.translation.width < 0 {
                                    offset = max(value.translation.width, -60)
                                }
                            }
                        }
                        .onEnded { value in
                            withAnimation {
                                if value.translation.width < -50 {
                                    isSwiped = true
                                    offset = -60
                                } else {
                                    isSwiped = false
                                    offset = 0
                                }
                            }
                        }
                )
        }
    }
} 