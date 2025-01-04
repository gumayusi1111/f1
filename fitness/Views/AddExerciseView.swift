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
    
    init(onExerciseAdded: @escaping (Exercise) -> Void) {
        self.onExerciseAdded = onExerciseAdded
    }
    
    // MARK: - Computed Properties
    private var isFormValid: Bool {
        !name.isEmpty && selectedCategory != nil && selectedUnit != nil
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
                            TextField("例如：卧推", text: $name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 16))
                            
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
    }
    
    // MARK: - Functions
    private func saveExercise() {
        guard isFormValid else { return }
        
        // 添加按钮动画
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            saveScale = 0.95
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                saveScale = 1
            }
        }
        
        isLoading = true
        print("\n========== 开始保存训练项目 ==========")
        print("📝 项目名称: \(name)")
        print("📑 类别: \(selectedCategory ?? "未选择")")
        print("📏 单位: \(selectedUnit ?? "未选择")")
        
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
        
        // 保存到 Firestore
        let db = Firestore.firestore()
        guard !userId.isEmpty else {
            showError = true
            errorMessage = "用户ID不存在"
            isLoading = false
            print("❌ 保存失败: 用户ID不存在")
            return
        }
        
        print("🔄 正在保存到 Firestore...")
        
        db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
            .setData(exercise.dictionary) { error in
                if let error = error {
                    showError = true
                    errorMessage = "保存失败: \(error.localizedDescription)"
                    isLoading = false
                    print("❌ 保存失败: \(error.localizedDescription)")
                } else {
                    // 1. 触觉反馈
                    let notificationGenerator = UINotificationFeedbackGenerator()
                    notificationGenerator.prepare() // 提前准备减少延迟
                    notificationGenerator.notificationOccurred(.success)
                    
                    // 2. 播放系统音效
                    AudioServicesPlaySystemSound(1004) // 使用系统提示音
                    
                    // 3. 显示成功动画
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        showSuccessToast = true
                        showSaveAnimation = true
                    }
                    
                    onExerciseAdded(exercise)
                    
                    // 延迟关闭
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showSuccessToast = false
                            showSaveAnimation = false
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isLoading = false
                            dismiss()
                        }
                    }
                }
                
                print("========== 保存结束 ==========\n")
            }
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

#Preview {
    AddExerciseView { _ in }
} 