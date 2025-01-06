import SwiftUI
import FirebaseFirestore
import CoreHaptics

struct AddTrainingView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userId") private var userId: String = ""
    
    @State private var selectedBodyPart = "胸部"
    @State private var selectedExercise: Exercise? = nil
    @State private var duration = ""
    @State private var sets = 3  // 组数
    @State private var reps = 12 // 次数
    @State private var weight = "" // 重量
    @State private var notes = ""
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var exercises: [Exercise] = []
    @State private var todayRecords: [TrainingRecord] = [] // 今日记录
    @State private var engine: CHHapticEngine?
    @AppStorage("todayTrainingPart") private var todayTrainingPart: String = "" // 存储今日训练部位
    
    let bodyParts = ["全部", "胸部", "背部", "腿部", "肩部", "手臂", "核心"]
    var onTrainingAdded: () -> Void
    
    init(date: Date, onTrainingAdded: @escaping () -> Void) {
        self.date = date
        self.onTrainingAdded = onTrainingAdded
        
        // 如果有今日训练部位,则使用它;否则默认显示"全部"
        _selectedBodyPart = State(initialValue: todayTrainingPart.isEmpty ? "全部" : todayTrainingPart)
        
        // 打印日志便于调试
        print("📅 初始化训练视图 - 日期: \(date)")
        print("💪 今日训练部位: \(todayTrainingPart.isEmpty ? "未设置" : todayTrainingPart)")
    }
    
    private var filteredExercises: [Exercise] {
        exercises.filter { exercise in
            let matchesSearch = searchText.isEmpty || 
                exercise.name.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedBodyPart == "全部" || 
                exercise.category == selectedBodyPart
            return matchesSearch && matchesCategory
        }
    }
    
    private func clearAllInputs() {
        searchText = ""
        selectedExercise = nil
        sets = 3
        reps = 12
        weight = ""
        notes = ""
    }
    
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Haptics error: \(error.localizedDescription)")
        }
    }
    
    private func playHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        var events = [CHHapticEvent]()
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        events.append(event)
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error.localizedDescription)")
        }
    }
    
    private var categoryCounts: [String: Int] {
        var counts: [String: Int] = [:]
        
        // 计算全部数量
        counts["全部"] = exercises.count
        
        // 计算每个分类的数量
        for bodyPart in bodyParts where bodyPart != "全部" {
            counts[bodyPart] = exercises.filter { $0.category == bodyPart }.count
        }
        
        return counts
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 训练部位选择器
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(bodyParts, id: \.self) { part in
                            BodyPartButton(
                                part: part,
                                count: categoryCounts[part] ?? 0,
                                isSelected: selectedBodyPart == part,
                                action: { 
                                    withAnimation { 
                                        selectedBodyPart = part 
                                        playHapticFeedback()
                                        if part != "全部" {
                                            todayTrainingPart = part
                                            saveTrainingPart()
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
                
                // 今日训练记录
                if !todayRecords.isEmpty {
                    TodayTrainingSection(records: todayRecords)
                }
                
                // 搜索栏
                TrainingSearchBar(
                    text: $searchText,
                    onClear: clearAllInputs
                )
                .padding()
                
                // 训练项目列表
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredExercises) { exercise in
                            ExerciseCard(
                                exercise: exercise,
                                isSelected: selectedExercise?.id == exercise.id,
                                onSelect: {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedExercise = exercise
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
                
                // 训练详情输入区域
                if let exercise = selectedExercise {
                    Spacer()
                    TrainingDetailSection(
                        exercise: exercise,
                        sets: $sets,
                        reps: $reps,
                        weight: $weight,
                        notes: $notes
                    )
                    .transition(.move(edge: .bottom))
                }
                
                // 完成按钮
                Button(action: addTraining) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("完成").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    selectedExercise == nil || weight.isEmpty ? 
                        Color.gray.opacity(0.3) : Color.blue
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding()
                .disabled(selectedExercise == nil || weight.isEmpty || isLoading)
            }
            .navigationTitle("添加训练")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("取消") { dismiss() })
            .background(Color(.systemGroupedBackground))
            .onAppear {
                prepareHaptics()
                loadExercises()
                loadTodayRecords()
                
                // 如果有今日训练部位,自动滚动到对应分类
                if !todayTrainingPart.isEmpty {
                    withAnimation {
                        selectedBodyPart = todayTrainingPart
                    }
                }
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // 加载训练项目
    private func loadExercises() {
        let db = Firestore.firestore()
        
        // 创建 DispatchGroup 来协调两个异步请求
        let group = DispatchGroup()
        var allExercises: [Exercise] = []
        
        // 加载系统预设项目
        group.enter()
        db.collection("systemExercises")
            .getDocuments { snapshot, error in
                defer { group.leave() }
                
                if let documents = snapshot?.documents {
                    let systemExercises = documents.compactMap { doc in
                        try? doc.data(as: Exercise.self)
                    }
                    allExercises.append(contentsOf: systemExercises)
                }
            }
        
        // 加载用户自定义项目
        group.enter()
        db.collection("users")
            .document(userId)
            .collection("exercises")
            .getDocuments { snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    return
                }
                
                if let documents = snapshot?.documents {
                    let userExercises = documents.compactMap { doc in
                        try? doc.data(as: Exercise.self)
                    }
                    allExercises.append(contentsOf: userExercises)
                }
            }
        
        // 当两个请求都完成时更新 UI
        group.notify(queue: .main) {
            self.exercises = allExercises
        }
    }
    
    private func addTraining() {
        guard let exercise = selectedExercise,
              let weightValue = Double(weight),
              !exercise.name.isEmpty else { return }
        
        isLoading = true
        let db = Firestore.firestore()
        
        let trainingData: [String: Any] = [
            "type": exercise.name,
            "bodyPart": selectedBodyPart,
            "sets": sets,
            "reps": reps,
            "weight": weightValue,
            "notes": notes,
            "date": date,
            "userId": userId
        ]
        
        db.collection("users")
            .document(userId)
            .collection("trainings")
            .addDocument(data: trainingData) { error in
                isLoading = false
                
                if let error = error {
                    errorMessage = "添加失败: \(error.localizedDescription)"
                    showError = true
                } else {
                    onTrainingAdded()
                    dismiss()
                }
            }
    }
    
    private func loadTodayRecords() {
        let db = Firestore.firestore()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        db.collection("users")
            .document(userId)
            .collection("trainings")
            .whereField("date", isGreaterThanOrEqualTo: startOfDay)
            .whereField("date", isLessThan: endOfDay)
            .getDocuments(source: .default) { snapshot, error in
                if let documents = snapshot?.documents {
                    self.todayRecords = documents.compactMap { doc in
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
    
    private func saveTrainingPart() {
        guard selectedBodyPart != "全部" else { return }
        
        let db = Firestore.firestore()
        let trainingPartData: [String: Any] = [
            "bodyPart": selectedBodyPart,
            "date": date,
            "userId": userId
        ]
        
        db.collection("users")
            .document(userId)
            .collection("trainingParts")
            .document(date.formatDate())
            .setData(trainingPartData) { error in
                if let error = error {
                    errorMessage = "保存训练部位失败: \(error.localizedDescription)"
                    showError = true
                }
            }
    }
}

// MARK: - 辅助视图组件

struct BodyPartButton: View {
    let part: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: bodyPartIcon(part))
                    .font(.system(size: 24))
                
                VStack(spacing: 4) {
                    Text(part)
                        .font(.system(size: 14))
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(width: 80, height: 80)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(12)
            .shadow(color: isSelected ? Color.blue.opacity(0.3) : .clear, radius: 4)
        }
    }
    
    private func bodyPartIcon(_ part: String) -> String {
        switch part {
        case "胸部": return "figure.arms.open"
        case "背部": return "figure.walk"
        case "腿部": return "figure.run"
        case "肩部": return "figure.boxing"
        case "手臂": return "figure.strengthtraining.traditional"
        case "核心": return "figure.core.training"
        default: return "figure.mixed.cardio"
        }
    }
}

struct ExerciseCard: View {
    let exercise: Exercise
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // 左侧图标
                exerciseIcon
                
                // 中间内容
                exerciseInfo
                
                Spacer()
            }
            .padding()
            .background(cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var exerciseIcon: some View {
        Circle()
            .fill(isSelected ? Color.blue : Color(.systemGray6))
            .frame(width: 50, height: 50)
            .overlay(
                Image(systemName: isSelected ? "checkmark" : "dumbbell.fill")
                    .foregroundColor(isSelected ? .white : .blue)
            )
    }
    
    private var exerciseInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.headline)
            if let unit = exercise.unit {
                Text("单位: \(unit)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.05), radius: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : .clear, lineWidth: 2)
            )
    }
}

struct TrainingSearchBar: View {
    @Binding var text: String
    let onClear: () -> Void
    
    var body: some View {
        HStack {
            // 搜索图标
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .padding(.leading, 8)
            
            // 搜索输入框
            TextField("搜索训练项目", text: $text)
                .textFieldStyle(.plain)
                .padding(.vertical, 10)
            
            // 清除按钮
            if !text.isEmpty {
                Button(action: {
                    text = ""
                    onClear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .padding(.trailing, 8)
                }
            }
        }
        .background(Color(.systemBackground)) // 白色背景
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1) // 添加边框
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1) // 添加轻微阴影
    }
}

// 今日训练记录部分
struct TodayTrainingSection: View {
    let records: [TrainingRecord]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader
            recordsList
        }
        .padding(.vertical)
        .background(Color(.systemGray6).opacity(0.5))
    }
    
    private var sectionHeader: some View {
        Text("今日已完成")
            .font(.headline)
            .padding(.horizontal)
    }
    
    private var recordsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(records) { record in
                    TrainingRecordCard(record: record)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct TrainingRecordCard: View {
    let record: TrainingRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.type)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("\(record.sets)组 × \(record.reps)次")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("\(Int(record.weight))kg")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

// 训练详情输入部分
struct TrainingDetailSection: View {
    let exercise: Exercise
    @Binding var sets: Int
    @Binding var reps: Int
    @Binding var weight: String
    @Binding var notes: String
    
    var body: some View {
        VStack(spacing: 20) {
            // 顶部把手示意
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.systemGray4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            
            // 标题
            Text(exercise.name)
                .font(.headline)
                .padding(.bottom, 5)
            
            // 主要输入区域
            HStack(spacing: 25) {
                // 组数选择器
                NumberPickerColumn(
                    title: "组数",
                    value: $sets,
                    range: 1...10,
                    tint: .blue
                )
                
                // 分隔线
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 1, height: 80)
                
                // 次数选择器
                NumberPickerColumn(
                    title: "次数",
                    value: $reps,
                    range: 1...30,
                    tint: .blue
                )
                
                // 分隔线
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 1, height: 80)
                
                // 重量输入
                WeightInputColumn(weight: $weight)
            }
            .padding(.vertical, 10)
            
            // 备注输入
            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("添加备注", text: $notes)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 15))
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.05), radius: 5, y: -2)
    }
}

// 添加数字选择器列组件
struct NumberPickerColumn: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let tint: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Picker("", selection: $value) {
                ForEach(range, id: \.self) { num in
                    Text("\(num)")
                        .tag(num)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 100)
            .clipped()
        }
    }
}

// 添加重量输入列组件
struct WeightInputColumn: View {
    @Binding var weight: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text("重量")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(alignment: .center, spacing: 4) {
                TextField("0", text: $weight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Text("kg")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(height: 100, alignment: .center)
        }
    }
}

// 添加圆角扩展
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}