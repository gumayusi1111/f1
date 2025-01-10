import SwiftUI
import FirebaseFirestore
import AudioToolbox // 修改为 AudioToolbox

struct AddExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userId") private var userId: String = ""
    
    // 表单状态
    @State private var name = ""
    @State private var selectedCategory: String?
    @State private var description = ""
    @State private var notes = ""
    @State private var selectedUnit: String?
    
    // UI 状态
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccessToast = false
    
    // 常量
    private let categories = ["胸部", "背部", "腿部", "肩部", "手臂", "核心", "有氧"]
    private let units = [
        "重量类": ["kg", "lbs"],
        "距离类": ["km", "m", "mile"],
        "时间类": ["分钟", "秒"],
        "次数类": ["次", "组"]
    ]
    
    // 添加单位选择状态
    @State private var selectedUnitCategory: String = "重量类"
    
    // 回调函数
    var onExerciseAdded: (Exercise) -> Void
    
    // 添加动画状态
    @State private var showSaveAnimation = false
    @State private var saveScale: CGFloat = 1
    
    // 在 AddExerciseView 中添加状态
    @State private var nameError: String? = nil  // 添加错误状态
    @State private var isCheckingName = false    // 添加检查状态
    
    // 在 AddExerciseView 结构体顶部添加状态
    @State private var isOffline = false
    @AppStorage("pendingExercises") private var pendingExercisesData: Data = Data()
    
    // 添加状态用于存储已有项目
    @State private var existingExercises: [Exercise] = []
    
    init(onExerciseAdded: @escaping (Exercise) -> Void) {
        self.onExerciseAdded = onExerciseAdded
    }
    
    // MARK: - Computed Properties
    private var isFormValid: Bool {
        // 1. 检查基本条件
        guard !name.isEmpty && 
              name.count >= 2 && 
              name.count <= 30 && 
              selectedCategory != nil && 
              selectedUnit != nil else {
            return false
        }
        
        // 2. 检查是否有错误
        if let error = validateName(name) {
            print("❌ 表单验证失败: \(error)")
            return false
        }
        
        // 3. 检查是否是系统预设
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let isSystemPreset = existingExercises.contains { exercise in
            exercise.isSystemPreset && 
            exercise.name.lowercased() == trimmedName.lowercased()
        }
        
        if isSystemPreset {
            print("❌ 表单验证失败: 系统预设项目")
            return false
        }
        
        print("✅ 表单验证通过")
        return true
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // 名称输入
                    VStack(alignment: .leading, spacing: 12) {
                        Label("项目名称", systemImage: "dumbbell.fill")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            TextField("例如：卧推", text: Binding(
                                get: { self.name },
                                set: { 
                                    self.name = $0
                                    print("\n========== 名称输入验证 ==========")
                                    print("📝 输入内容: \($0)")
                                    
                                    // 使用完整的验证函数
                                    self.nameError = validateName($0)
                                    
                                    // 打印验证结果
                                    if let error = self.nameError {
                                        print("❌ 验证失败: \(error)")
                                    } else {
                                        print("✅ 验证通过")
                                    }
                                    print("===================================\n")
                                }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .overlay(
                                Group {
                                    if let error = nameError {
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                            .padding(.top, 40)
                                    }
                                },
                                alignment: .bottom
                            )
                            
                            if !name.isEmpty {
                                Button(action: { name = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 18))
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
                        )
                    }
                    
                    // 类别选择
                    VStack(alignment: .leading, spacing: 12) {
                        Label("选择类别", systemImage: "tag.fill")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(categories, id: \.self) { category in
                                    SelectableButton(
                                        title: category,
                                        isSelected: selectedCategory == category,
                                        action: { selectedCategory = category },
                                        color: getCategoryColor(category)
                                    )
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // 计量单位选择
                    VStack(alignment: .leading, spacing: 12) {
                        Label("计量单位", systemImage: "ruler.fill")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            // 单位类别选择
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(units.keys.sorted()), id: \.self) { category in
                                        SelectableButton(
                                            title: category,
                                            isSelected: selectedUnitCategory == category,
                                            action: { 
                                                withAnimation {
                                                    selectedUnitCategory = category
                                                    selectedUnit = nil
                                                }
                                            },
                                            color: .blue
                                        )
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                            }
                            
                            // 具体单位选择
                            if let unitOptions = units[selectedUnitCategory] {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(unitOptions, id: \.self) { unit in
                                            SelectableButton(
                                                title: unit,
                                                isSelected: selectedUnit == unit,
                                                action: { selectedUnit = unit },
                                                color: .orange
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 4)
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                    
                    // 可选输入区域
                    VStack(alignment: .leading, spacing: 24) {
                        OptionalInputField(
                            title: "描述",
                            subtitle: "可选",
                            icon: "text.alignleft",
                            text: $description,
                            placeholder: "描述这个训练项目..."
                        )
                        
                        OptionalInputField(
                            title: "注意事项",
                            subtitle: "可选",
                            icon: "exclamationmark.triangle",
                            text: $notes,
                            placeholder: "添加训练注意事项..."
                        )
                    }
                    
                    // 保存按钮
                    Button(action: saveExercise) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isLoading ? "保存中..." : "保存")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isFormValid ? Color.blue : Color(.systemGray4))
                                .shadow(color: isFormValid ? Color.blue.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                        )
                        .foregroundColor(.white)
                        .opacity(isLoading ? 0.7 : 1)
                        .scaleEffect(saveScale)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: saveScale)
                    }
                    .disabled(!isFormValid || isLoading)
                    .padding(.top, 16)
                    
                    // 修改 overlay 部分
                    .overlay {
                        if showSuccessToast {
                            SaveSuccessView()
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("添加项目")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { dismiss() }
                    .foregroundColor(.blue)
            )
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            // 视图加载时获取已有项目
            await loadExistingExercises()
        }
    }
    
    // MARK: - Functions
    private func saveExercise() {
        Task {
            guard isFormValid else { return }
            
            // 创建运动项目
            let exercise = Exercise(
                id: UUID().uuidString,
                name: name,
                category: selectedCategory!,
                description: description,
                notes: notes,
                isSystemPreset: false,
                unit: selectedUnit,
                createdAt: Date(),
                updatedAt: Date(),
                maxRecord: nil,
                lastRecordDate: nil
            )
            
            print("\n========== 开始保存训练项目 ==========")
            print("📱 检查网络状态...")
            
            // 检查网络连接
            do {
                let db = Firestore.firestore()
                try await db.collection("users").document("test").getDocument(source: .server)
                isOffline = false
                print("✅ 网络连接正常")
                
                // 添加在线保存逻辑
                print("🔄 开始在线保存...")
                guard !userId.isEmpty else {
                    print("❌ 保存失败: 用户ID不存在")
                    throw ExerciseError.invalidUserId
                }
                
                try await db.collection("users")
                    .document(userId)
                    .collection("exercises")
                    .document(exercise.id)
                    .setData(exercise.dictionary)
                
                print("✅ 在线保存成功")
                
                // 触觉反馈
                let notificationGenerator = UINotificationFeedbackGenerator()
                notificationGenerator.prepare()
                notificationGenerator.notificationOccurred(.success)
                
                // 播放系统音效
                AudioServicesPlaySystemSound(1004)
                
                // 回调通知
                onExerciseAdded(exercise)
                
                // 显示成功动画
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showSuccessToast = true
                    showSaveAnimation = true
                }
                
                // 延迟关闭
                try await Task.sleep(for: .seconds(1.5))
                withAnimation {
                    showSuccessToast = false
                    showSaveAnimation = false
                }
                isLoading = false
                dismiss()
                
                print("========== 保存完成 ==========\n")
                
            } catch {
                isOffline = true
                print("⚠️ 当前处于离线状态或保存失败")
                print("错误信息: \(error.localizedDescription)")
                
                // 保存到待处理队列
                var pendingExercises = getPendingExercises()
                pendingExercises.append(exercise)
                savePendingExercises(pendingExercises)
                
                // 显示成功提示
                showOfflineSuccess()
                print("📝 已保存到离线队列")
                print("待同步项目数: \(pendingExercises.count)")
            }
        }
    }
    
    // 添加辅助函数
    private func getPendingExercises() -> [Exercise] {
        guard let exercises = try? JSONDecoder().decode([Exercise].self, from: pendingExercisesData) else {
            return []
        }
        return exercises
    }
    
    private func savePendingExercises(_ exercises: [Exercise]) {
        if let data = try? JSONEncoder().encode(exercises) {
            pendingExercisesData = data
        }
    }
    
    private func showOfflineSuccess() {
        // 使用现有的成功动画
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            showSuccessToast = true
            showSaveAnimation = true
        }
        
        // 延迟关闭动画
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation {
                showSuccessToast = false
                showSaveAnimation = false
            }
            isLoading = false
            dismiss()
        }
    }
    
    // 添加同步函数 (在恢复网络时调用)
    private func syncPendingExercises() async {
        let pendingExercises = getPendingExercises()
        guard !pendingExercises.isEmpty else { return }
        
        print("\n========== 开始同步离线数据 ==========")
        print("📝 待同步项目数: \(pendingExercises.count)")
        
        let db = Firestore.firestore()
        var syncedCount = 0
        
        for exercise in pendingExercises {
            do {
                try await db.collection("users")
                    .document(userId)
                    .collection("exercises")
                    .document(exercise.id)
                    .setData(exercise.dictionary)
                syncedCount += 1
                print("✅ 同步成功: \(exercise.name)")
            } catch {
                print("❌ 同步失败: \(exercise.name)")
                print("错误信息: \(error.localizedDescription)")
            }
        }
        
        print("📊 同步结果:")
        print("- 成功: \(syncedCount)")
        print("- 失败: \(pendingExercises.count - syncedCount)")
        
        // 清除已同步的数据
        if syncedCount == pendingExercises.count {
            pendingExercisesData = Data()
            print("🧹 清理离线队列")
        }
        
        print("========== 同步结束 ==========\n")
    }
    
    // 添加名称重复检查函数
    private func checkNameDuplicate() async -> Bool {
        print("\n========== 开始检查名称重复 ==========")
        print("📝 检查名称: \(name)")
        
        let db = Firestore.firestore()
        do {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            print("🔍 处理后的名称: \(trimmedName)")
            
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("exercises")
                .whereField("name", isEqualTo: trimmedName)
                .getDocuments()
            
            let isDuplicate = !snapshot.documents.isEmpty
            print(isDuplicate ? "❌ 发现重复名称" : "✅ 名称可用")
            print("========== 检查结束 ==========\n")
            return isDuplicate
        } catch {
            print("❌ 检查失败: \(error)")
            print("========== 检查异常结束 ==========\n")
            return false
        }
    }
    
    // 修改加载函数
    private func loadExistingExercises() async {
        print("\n========== 开始加载项目 ==========")
        let db = Firestore.firestore()
        
        do {
            // 1. 加载用户自定义项目
            print("📱 加载用户自定义项目...")
            let userSnapshot = try await db.collection("users")
                .document(userId)
                .collection("exercises")
                .getDocuments()
            
            let userExercises = userSnapshot.documents.compactMap { doc -> Exercise? in
                return Exercise(dictionary: doc.data(), id: doc.documentID)
            }
            print("✅ 用户项目数量: \(userExercises.count)")
            
            // 2. 加载系统预设项目
            print("\n📱 加载系统预设项目...")
            let systemSnapshot = try await db.collection("systemExercises")
                .getDocuments()
            
            let systemExercises = systemSnapshot.documents.compactMap { doc -> Exercise? in
                return Exercise(dictionary: doc.data(), id: doc.documentID)
            }
            print("✅ 系统预设数量: \(systemExercises.count)")
            
            // 3. 合并两个列表
            existingExercises = userExercises + systemExercises
            
            // 4. 打印详细统计
            print("\n📊 项目统计:")
            print("- 用户自定义: \(userExercises.count)")
            print("- 系统预设: \(systemExercises.count)")
            print("- 总计: \(existingExercises.count)")
            
            // 5. 按类别统计
            let categoryCounts = Dictionary(grouping: existingExercises) { $0.category }
                .mapValues { $0.count }
            print("\n📊 类别统计:")
            for (category, count) in categoryCounts.sorted(by: { $0.key < $1.key }) {
                print("- \(category): \(count)")
            }
            
            print("✅ 加载完成")
        } catch {
            print("❌ 加载失败: \(error.localizedDescription)")
        }
        print("========== 加载结束 ==========\n")
    }
    
    // 添加辅助函数用于检查是否是系统预设
    private func isSystemPreset(_ name: String) -> Bool {
        return existingExercises.contains { exercise in
            exercise.isSystemPreset && exercise.name.lowercased() == name.lowercased()
        }
    }
    
    // 修改名称验证逻辑
    private func validateName(_ name: String) -> String? {
        print("\n========== 开始完整验证 ==========")
        print("📝 当前名称: \(name)")
        print("📊 existingExercises 数组长度: \(existingExercises.count)")
        
        // 打印所有系统预设项目
        print("\n🔍 系统预设项目列表:")
        existingExercises.filter { $0.isSystemPreset }.forEach { exercise in
            print("- \(exercise.name) (isSystemPreset: \(exercise.isSystemPreset))")
        }
        
        // 基本验证
        if name.isEmpty {
            print("❌ 验证失败: 名称为空")
            return "请输入项目名称"
        }
        
        if name.count < 2 {
            print("❌ 验证失败: 名称过短")
            return "名称至少需要2个字符"
        }
        
        if name.count > 30 {
            print("❌ 验证失败: 名称过长")
            return "名称不能超过30个字符"
        }
        
        // 重复验证
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        print("\n🔍 开始重复检查:")
        print("- 处理后的名称: \(trimmedName)")
        
        // 先检查是否是系统预设
        let systemPresetMatches = existingExercises.filter { exercise in
            let isMatch = exercise.isSystemPreset && 
                         exercise.name.lowercased() == trimmedName.lowercased()
            if isMatch {
                print("⚠️ 发现系统预设匹配: \(exercise.name) (ID: \(exercise.id))")
            }
            return isMatch
        }
        
        if !systemPresetMatches.isEmpty {
            print("❌ 验证失败: 与系统预设重复")
            print("- 匹配的系统预设数量: \(systemPresetMatches.count)")
            systemPresetMatches.forEach { exercise in
                print("- 匹配项目: \(exercise.name)")
            }
            print("========== 验证结束 ==========\n")
            return "该名称为系统预设项目，请使用其他名称"
        }
        
        // 再检查用户自定义项目
        let userMatches = existingExercises.filter { exercise in
            let isMatch = !exercise.isSystemPreset && 
                         exercise.name.lowercased() == trimmedName.lowercased()
            if isMatch {
                print("⚠️ 发现用户项目匹配: \(exercise.name) (ID: \(exercise.id))")
            }
            return isMatch
        }
        
        print("\n📊 检查结果:")
        print("- 总项目数: \(existingExercises.count)")
        print("- 系统预设匹配数: \(systemPresetMatches.count)")
        print("- 用户项目匹配数: \(userMatches.count)")
        
        if !userMatches.isEmpty {
            print("❌ 验证失败: 名称重复")
            return "该项目名称已存在"
        }
        
        print("✅ 验证通过")
        print("========== 验证结束 ==========\n")
        return nil
    }
}

// MARK: - Supporting Views
private struct SelectableButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    let color: Color
    
    var body: some View {
        Button(action: {
            // 1. 触觉反馈
            let impactGenerator = UIImpactFeedbackGenerator(style: .light)
            impactGenerator.prepare()
            impactGenerator.impactOccurred()
            
            // 2. 播放按钮音效
            AudioServicesPlaySystemSound(1104) // 使用系统按钮音效
            
            action()
        }) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? color : Color(.systemGray6))
                        .shadow(color: isSelected ? color.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                )
                .foregroundColor(isSelected ? .white : .primary)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
    }
}

private struct OptionalInputField: View {
    let title: String
    let subtitle: String
    let icon: String
    let text: Binding<String>
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(.systemGray6))
                    )
            }
            
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(3...6)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
                )
        }
    }
}

// 添加成功动画视图
private struct SaveSuccessView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("保存成功")
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                scale = 1
                opacity = 1
            }
        }
    }
}

// MARK: - Helper Functions
private func getCategoryColor(_ category: String) -> Color {
    switch category {
    case "胸部": return .red
    case "背部": return .blue
    case "腿部": return .purple
    case "肩部": return .orange
    case "手臂": return .green
    case "核心": return .pink
    case "有氧": return .cyan
    default: return .blue
    }
}

// 添加错误类型
enum ExerciseError: Error {
    case invalidUserId
    
    var localizedDescription: String {
        switch self {
        case .invalidUserId:
            return "用户ID不存在"
        }
    }
}

#Preview {
    AddExerciseView { _ in }
} 