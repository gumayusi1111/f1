import SwiftUI
import FirebaseFirestore
import CoreHaptics

struct AddTrainingView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userId") private var userId: String = ""
    
    @State private var filterBodyPart: String  // 改名为 filterBodyPart，表示这只是筛选用
    @State private var selectedExercise: Exercise? = nil
    @State private var duration = ""
    @State private var sets = 1  // 组数
    @State private var reps = 8  // 次数
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
    
    // 添加数值选择器的状态变量
    @State private var selectedIntegerPart = 1
    @State private var selectedDecimalPart = 0
    
    let bodyParts = ["全部", "胸部", "背部", "腿部", "肩部", "手臂", "核心"]
    var onTrainingAdded: () -> Void
    
    // 添加缓存相关的属性
    private let exercisesCacheKey = "cachedExercises"
    private let exercisesCacheTimeKey = "exercisesCacheTime"
    private let cacheValidDuration: TimeInterval = 24 * 60 * 60 // 24小时
    
    // 在 WeightInputColumn 中添加 UserDefaults key
    private let lastTrainingValueKey = "lastTrainingValue_" // 将跟随运动ID存储
    
    // 添加动画相关状态
    @State private var isCompleting = false
    @State private var showSuccessOverlay = false
    
    init(date: Date, onTrainingAdded: @escaping () -> Void) {
        self.date = date
        self.onTrainingAdded = onTrainingAdded
        
        // 初始化筛选部位为"全部"，不使用今日训练部位
        _filterBodyPart = State(initialValue: "全部")
        
        print("📅 初始化训练视图 - 日期: \(date)")
        print("🔍 初始筛选部位: 全部")
    }
    
    private var filteredExercises: [Exercise] {
        exercises.filter { exercise in
            let matchesSearch = searchText.isEmpty || 
                exercise.name.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = filterBodyPart == "全部" || 
                exercise.category == filterBodyPart
            return matchesSearch && matchesCategory
        }
    }
    
    private func clearAllInputs() {
        searchText = ""
        selectedExercise = nil
        sets = 1
        reps = 8
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
    
    private func hideTrainingDetail() {
        withAnimation(.easeOut(duration: 0.2)) {
            selectedExercise = nil
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 训练部位选择器
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(bodyParts, id: \.self) { part in
                            Button(action: {
                                withAnimation {
                                    filterBodyPart = part
                                    hideTrainingDetail()
                                    playHapticFeedback()
                                }
                            }) {
                                BodyPartButton(
                                    part: part,
                                    count: categoryCounts[part] ?? 0,
                                    isSelected: filterBodyPart == part,
                                    action: { 
                                        withAnimation { 
                                            hideTrainingDetail()
                                            filterBodyPart = part 
                                            playHapticFeedback()
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
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
                                    if selectedExercise?.id == exercise.id {
                                        hideTrainingDetail()
                                        return
                                    }
                                    // 先隐藏当前详情
                                    hideTrainingDetail()
                                    // 短暂延迟后显示新选择的项目
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedExercise = exercise
                                            // 加载选中项目的历史记录
                                            loadLastRecord(for: exercise)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
                .simultaneousGesture(
                    // 添加滑动手势，当用户滑动列表时收起详情
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in
                            hideTrainingDetail()
                        }
                )
                
                // 训练详情输入区域
                if let exercise = selectedExercise {
                    Spacer()
                    TrainingDetailSection(
                        exercise: exercise,
                        sets: $sets,
                        reps: $reps,
                        weight: $weight,
                        notes: $notes,
                        onDismiss: {
                            hideTrainingDetail()
                        }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                }
                
                // 完成按钮
                Button(action: addTraining) {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("完成")
                                .fontWeight(.semibold)
                                .scaleEffect(isCompleting ? 0.9 : 1)
                        }
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
                .scaleEffect(isCompleting ? 0.95 : 1)
                .animation(.spring(response: 0.3), value: isCompleting)
            }
            .overlay {
                if showSuccessOverlay {
                    // 成功提示遮罩
                    VStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                            .transition(.scale.combined(with: .opacity))
                        
                        Text("训练已添加")
                            .font(.title3)
                            .foregroundColor(.primary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
                    .transition(.opacity)
                }
            }
            // 添加页面过渡动画
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
            .navigationTitle("添加训练")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("取消") { dismiss() })
            .background(Color(.systemGroupedBackground))
            .onAppear {
                prepareHaptics()
                loadExercises()
                
                // 如果有今日训练部位,自动滚动到对应分类
                if !todayTrainingPart.isEmpty {
                    withAnimation {
                        filterBodyPart = todayTrainingPart
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
        // 先尝试从缓存加载
        if let cachedExercises = loadFromCache() {
            self.exercises = cachedExercises
            print("📦 从缓存加载训练项目: \(cachedExercises.count) 个")
            return
        }
        
        let db = Firestore.firestore()
        let group = DispatchGroup()
        var allExercises: [Exercise] = []
        
        // 加载系统预设项目
        group.enter()
        db.collection("systemExercises")
            .getDocuments { snapshot, error in
                defer { group.leave() }
                
                if let documents = snapshot?.documents {
                    print("📚 加载系统预设项目:")
                    for doc in documents {
                        if let exercise = try? doc.data(as: Exercise.self) {
                            print("  - 项目: \(exercise.name)")
                            print("  - ID: \(exercise.id)")
                            allExercises.append(exercise)
                        }
                    }
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
                    print("👤 加载用户自定义项目:")
                    for doc in documents {
                        if let exercise = try? doc.data(as: Exercise.self) {
                            print("  - 项目: \(exercise.name)")
                            print("  - ID: \(exercise.id)")
                            allExercises.append(exercise)
                        }
                    }
                }
            }
        
        group.notify(queue: .main) { [self] in
            self.exercises = allExercises
            print("✅ 加载完成，共 \(allExercises.count) 个项目")
            // 保存到缓存
            saveToCache(exercises: allExercises)
        }
    }
    
    // 缓存相关方法
    private func loadFromCache() -> [Exercise]? {
        guard let lastCacheTime = UserDefaults.standard.object(forKey: exercisesCacheTimeKey) as? Date else {
            return nil
        }
        
        // 检查缓存是否过期
        if Date().timeIntervalSince(lastCacheTime) > cacheValidDuration {
            print("⚠️ 缓存已过期")
            return nil
        }
        
        guard let data = UserDefaults.standard.data(forKey: exercisesCacheKey),
              let exercises = try? JSONDecoder().decode([Exercise].self, from: data) else {
            return nil
        }
        
        return exercises
    }
    
    private func saveToCache(exercises: [Exercise]) {
        guard let data = try? JSONEncoder().encode(exercises) else { return }
        UserDefaults.standard.set(data, forKey: exercisesCacheKey)
        UserDefaults.standard.set(Date(), forKey: exercisesCacheTimeKey)
        print("💾 训练项目已缓存: \(exercises.count) 个")
    }
    
    private func loadLastRecord(for exercise: Exercise) {
        let recordsPath = "users/\(userId)/exercises/\(exercise.id)/records"
        print("🔍 开始查询记录 - 路径: \(recordsPath)")
        
        Firestore.firestore().collection(recordsPath)
            .order(by: "date", descending: true)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ 查询失败: \(error.localizedDescription)")
                    return
                }
                
                if let document = snapshot?.documents.first,
                   let value = document.data()["value"] as? Double {
                    print("✅ 成功获取数值: \(value)")
                    
                    DispatchQueue.main.async {
                        // 1. 先更新 exercises 数组中的记录
                        if let index = self.exercises.firstIndex(where: { $0.id == exercise.id }) {
                            var updatedExercise = self.exercises[index]
                            updatedExercise.lastRecord = value
                            self.exercises[index] = updatedExercise
                            
                            // 2. 如果是当前选中的运动，更新 selectedExercise
                            if self.selectedExercise?.id == exercise.id {
                                self.selectedExercise = updatedExercise
                                
                                // 3. 设置初始值
                                self.selectedIntegerPart = Int(value)
                                self.selectedDecimalPart = Int((value.truncatingRemainder(dividingBy: 1)) * 100)
                                
                                // 4. 更新显示的值
                                self.updateValue()
                            }
                        }
                        
                        print("💾 更新成功 - \(exercise.name): \(value)")
                    }
                }
            }
    }
    
    private func updateValue() {
        guard let exercise = selectedExercise else { return }
        
        let finalValue = switch exercise.unit {
        case "次", "组":
            Double(selectedIntegerPart) + (selectedDecimalPart == 5 ? 0.5 : 0.0)
        case "秒":
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 10.0
        case "分钟":
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 60.0
        default:
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 100.0
        }
        
        weight = switch exercise.unit {
        case "次", "组", "秒":
            String(format: "%.1f", finalValue)
        default:
            String(format: "%.2f", finalValue)
        }
        
        print("📝 值已更新:")
        print("  - 整数部分: \(selectedIntegerPart)")
        print("  - 小数部分: \(selectedDecimalPart)")
        print("  - 最终值: \(weight)")
    }
    
    private func addTraining() {
        guard let exercise = selectedExercise,
              let weightValue = Double(weight),
              !exercise.name.isEmpty else { return }
        
        // 开始完成动画
        withAnimation(.spring(response: 0.3)) {
            isCompleting = true
        }
        
        isLoading = true
        let db = Firestore.firestore()
        
        let trainingData: [String: Any] = [
            "type": exercise.name,
            "bodyPart": filterBodyPart,
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
                    // 重置动画状态
                    withAnimation(.spring(response: 0.3)) {
                        isCompleting = false
                    }
                } else {
                    // 保存本次训练的值
                    UserDefaults.standard.set(weightValue, forKey: "lastTrainingValue_" + exercise.id)
                    
                    // 显示成功动画
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        showSuccessOverlay = true
                    }
                    
                    // 播放触觉反馈
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    
                    // 延迟关闭页面
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        onTrainingAdded()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            dismiss()
                        }
                    }
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

// 训练详情输入部分
struct TrainingDetailSection: View {
    let exercise: Exercise
    @Binding var sets: Int
    @Binding var reps: Int
    @Binding var weight: String
    @Binding var notes: String
    @GestureState private var dragState = DragState.inactive
    @State private var dragOffset: CGFloat = 0
    let dismissThreshold: CGFloat = 100 // 触发关闭的阈值
    var onDismiss: () -> Void
    
    enum DragState {
        case inactive
        case dragging(translation: CGFloat)
        
        var translation: CGFloat {
            switch self {
            case .inactive:
                return 0
            case .dragging(let translation):
                return translation
            }
        }
    }
    
    // 添加状态变量用于整数和小数部分选择
    @State private var selectedIntegerPart: Int = 0
    @State private var selectedDecimalPart: Int = 0
    
    // 添加状态来控制视图的显示
    @State private var isDismissing = false
    
    // 添加整数范围计算属性
    private var integerRange: [Int] {
        switch exercise.unit {
        case "次", "组":
            return Array(0...30)
        case "秒":
            return Array(0...60)
        case "分钟":
            return Array(0...30)
        case "m":
            return Array(0...100)
        case "km", "mile":
            return Array(0...20)
        default: // kg, lbs 等重量单位
            return Array(0...200)
        }
    }
    
    // 添加小数部分选项
    private var decimalParts: [Int] {
        switch exercise.unit {
        case "秒":
            return Array(0...9)
        case "分钟":
            return Array(0...59)
        case "m":
            return [0, 5]
        case "km", "mile":
            return [0, 25, 50, 75]
        default: // kg, lbs 等重量单位
            return [0, 25, 50, 75]
        }
    }
    
    // 格式化小数文本
    private func getDecimalText(value: Int) -> String {
        switch exercise.unit {
        case "分钟":
            return "\(value)秒"
        default:
            return String(format: "%02d", value)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 顶部把手示意
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            // 标题区域
            VStack(spacing: 4) {
                Text(exercise.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                if let unit = exercise.unit {
                    Text("单位: \(unit)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 10)
            
            // 主要输入区域
            HStack(spacing: 20) {
                // 组数选择器
                NumberPickerColumn(
                    title: "组数",
                    value: $sets,
                    range: 1...10,
                    tint: .blue,
                    icon: "number.square.fill"
                )
                
                Divider()
                    .frame(height: 80)
                
                // 次数选择器
                NumberPickerColumn(
                    title: "次数",
                    value: $reps,
                    range: 1...30,
                    tint: .blue,
                    icon: "repeat.circle.fill"
                )
                
                Divider()
                    .frame(height: 80)
                
                // 数值输入
                WeightInputColumn(
                    value: $weight,
                    exercise: exercise,
                    integerPart: $selectedIntegerPart,
                    decimalPart: $selectedDecimalPart
                )
            }
            .padding(.vertical, 10)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
            
            // 备注输入
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "note.text")
                        .foregroundColor(.secondary)
                    Text("备注")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                TextField("添加备注", text: $notes)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 15))
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
        .offset(y: max(0, dragState.translation + dragOffset))
        .opacity(isDismissing ? 0 : 1) // 添加透明度动画
        .gesture(
            DragGesture()
                .updating($dragState) { value, state, _ in
                    // 只在向下拖动时响应
                    if value.translation.height > 0 {
                        state = .dragging(translation: value.translation.height)
                    }
                }
                .onEnded { value in
                    let snapDistance = value.translation.height
                    if snapDistance > dismissThreshold {
                        // 先设置消失动画
                        withAnimation(.easeOut(duration: 0.2)) {
                            isDismissing = true
                            dragOffset = UIScreen.main.bounds.height
                        }
                        // 延迟调用实际的 dismiss
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDismiss()
                        }
                    } else {
                        // 回弹动画
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: dragState.translation)
    }
}

// 添加数字选择器列组件
struct NumberPickerColumn: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let tint: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(tint)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
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

// 修改 WeightInputColumn 组件
struct WeightInputColumn: View {
    @Binding var value: String
    let exercise: Exercise
    @Binding var integerPart: Int
    @Binding var decimalPart: Int
    
    @State private var isInitialized = false
    @State private var isLoading = true
    @State private var range: [Int] = []
    
    private func initializeValues() {
        print("\n📊 初始化值 - \(exercise.name):")
        
        // 获取上次训练值
        let lastValue = UserDefaults.standard.double(forKey: "lastTrainingValue_" + exercise.id)
        
        // 设置范围
        let defaultRange: [Int]
        if lastValue > 0 {
            // 如果有上次记录,使用 50%-150% 范围
            let baseValue = Int(lastValue)
            let minValue = max(1, Int(Double(baseValue) * 0.5))
            let maxValue = Int(Double(baseValue) * 1.5)
            defaultRange = Array(minValue...maxValue)
        } else {
            // 否则使用默认范围
            defaultRange = switch exercise.unit {
            case "kg", "lbs": Array(1...200)
            case "次", "组": Array(1...30)
            case "秒": Array(1...60)
            case "分钟": Array(1...60)
            case "m": Array(1...200)
            case "km", "mile": Array(1...30)
            default: Array(1...100)
            }
        }
        
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.range = defaultRange
                // 如果有上次记录,使用上次的值作为初始值
                self.integerPart = lastValue > 0 ? Int(lastValue) : defaultRange[0]
                self.decimalPart = lastValue > 0 ? 
                    Int((lastValue.truncatingRemainder(dividingBy: 1)) * 100) : 0
                self.isLoading = false
                self.isInitialized = true
            }
            
            print("📏 范围: \(defaultRange.first ?? 0)...\(defaultRange.last ?? 0)")
            print("🎯 初始值: \(self.integerPart).\(self.decimalPart)")
            
            self.updateValue()
        }
        
        print("✅ 初始化完成\n")
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: getUnitIcon())
                    .foregroundColor(.blue)
                Text(exercise.unit ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if isLoading {
                ProgressView()
                    .frame(height: 100)
            } else {
                HStack(spacing: 2) {
                    Picker("", selection: $integerPart) {
                        ForEach(range, id: \.self) { num in
                            Text("\(num)")
                                .tag(num)
                                .monospacedDigit()
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 70, height: 100)
                    .clipped()
                    .onChange(of: integerPart) { oldValue, newValue in
                        if !isLoading {
                            updateValue()
                        }
                    }
                    
                    Text(".")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 10)
                    
                    Picker("", selection: $decimalPart) {
                        ForEach(decimalParts, id: \.self) { num in
                            Text(getDecimalText(value: num))
                                .tag(num)
                                .monospacedDigit()
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 50, height: 100)
                    .clipped()
                    .onChange(of: decimalPart) { oldValue, newValue in
                        if !isLoading {
                            updateValue()
                        }
                    }
                }
            }
        }
        .onAppear {
            print("🔄 组件加载 - \(exercise.name)")
            initializeValues()
        }
    }
    
    // 根据单位类型返回对应图标
    private func getUnitIcon() -> String {
        switch exercise.unit {
        case "kg", "lbs": return "scalemass.fill"
        case "次", "组": return "number.circle.fill"
        case "秒": return "stopwatch.fill"
        case "分钟": return "clock.fill"
        case "m", "km", "mile": return "ruler.fill"
        default: return "number.circle.fill"
        }
    }
    
    // 添加更新值的方法
    private func updateValue() {
        print("💡 更新输入值:")
        print("  - 整数部分: \(integerPart)")
        print("  - 小数部分: \(decimalPart)")
        
        let finalValue = switch exercise.unit {
        case "次", "组":
            Double(integerPart) + (decimalPart == 5 ? 0.5 : 0.0)
        case "秒":
            Double(integerPart) + Double(decimalPart) / 10.0
        case "分钟":
            Double(integerPart) + Double(decimalPart) / 60.0
        default:
            Double(integerPart) + Double(decimalPart) / 100.0
        }
        
        value = switch exercise.unit {
        case "次", "组", "秒":
            String(format: "%.1f", finalValue)
        default:
            String(format: "%.2f", finalValue)
        }
        
        print("  - 最终值: \(value)")
    }
    
    // 计算小数部分选项
    private var decimalParts: [Int] {
        switch exercise.unit {
        case "次", "组":
            // 次数和组数只有 .0 和 .5
            return [0, 5]
        case "秒":
            // 秒数是 0-9
            return Array(0...9)
        case "分钟":
            // 分钟的小数是 0-59 秒
            return Array(0...59)
        case "m", "km", "mile", "kg", "lbs":
            // 距离和重量单位使用 .00, .25, .50, .75
            return [0, 25, 50, 75]
        default:
            return [0]
        }
    }
    
    private func getDecimalText(value: Int) -> String {
        switch exercise.unit {
        case "次", "组":
            // 次数和组数显示一位小数 (x.0 或 x.5)
            return value == 0 ? "0" : "5"
        case "秒":
            // 秒数显示一位小数 (x.0-x.9)
            return "\(value)"
        case "分钟":
            // 分钟显示秒数 (x分y秒)
            return "\(value)秒"
        case "m", "km", "mile", "kg", "lbs":
            // 距离和重量显示两位小数 (xx.00, xx.25, xx.50, xx.75)
            return value == 0 ? "00" : String(format: "%02d", value)
        default:
            return "0"
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