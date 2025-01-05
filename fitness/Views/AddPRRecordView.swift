import SwiftUI
import FirebaseFirestore
import AudioToolbox

struct AddPRRecordView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @State private var selectedValue: Double = 0.0
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var records: [ExerciseRecord] = []
    @State private var showSuccessAnimation = false
    @State private var isHistoryExpanded = false
    @State private var savedRecord: ExerciseRecord?
    @State private var showingDeleteAlert = false
    @State private var recordToDelete: ExerciseRecord?
    @State private var showDeleteSuccessAnimation = false
    @State private var deletedRecordId: String?
    var onRecordUpdate: (() -> Void)?
    
    // 修改滚轮选择器的范围计算
    private var valueRange: [Double] {
        var values: [Double] = []
        let baseValue = exercise.maxRecord ?? 50.0 // 使用当前记录或默认值
        let minValue = max(0, baseValue * 0.8) // 下限80%
        let maxValue = baseValue * 1.2 // 上限120%
        
        // 确保当前值在范围内
        var current = minValue
        while current <= maxValue {
            values.append(current)
            current += 0.5
        }
        
        // 如果当前记录值不在生成的范围内,添加它
        if let currentMax = exercise.maxRecord,
           !values.contains(currentMax) {
            values.append(currentMax)
            values.sort() // 保持数组有序
        }
        
        return values
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
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
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // 新记录选择器
                    VStack(spacing: 20) {
                        Text("添加新记录")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // 数值选择器
                        HStack {
                            Picker("选择数值", selection: $selectedValue) {
                                ForEach(valueRange, id: \.self) { value in
                                    Text("\(value, specifier: "%.1f")")
                                        .tag(value)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                            
                            Text(exercise.unit ?? "")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .padding(.leading)
                        }
                        .padding(.vertical, 8)
                        
                        // 保存按钮
                        Button(action: saveRecord) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("保存中...")
                                } else {
                                    Text("保存记录")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isLoading)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 2)
                    .padding(.horizontal)
                    
                    // 历史记录列表
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("历史记录")
                                .font(.headline)
                            Spacer()
                            if !records.isEmpty {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        isHistoryExpanded.toggle()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Text(isHistoryExpanded ? "收起" : "展开")
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                        Image(systemName: isHistoryExpanded ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 12))
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        if records.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("暂无历史记录")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(isHistoryExpanded ? records : Array(records.prefix(3))) { record in
                                    RecordRow(
                                        record: record,
                                        unit: exercise.unit ?? "",
                                        onDelete: {
                                            recordToDelete = record
                                            showingDeleteAlert = true
                                        },
                                        isDeleting: record.id == deletedRecordId
                                    )
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .move(edge: .trailing).combined(with: .opacity)
                                    ))
                                }
                            }
                        }
                    }
                    .alert("确认删除", isPresented: $showingDeleteAlert) {
                        Button("取消", role: .cancel) {}
                        Button("删除", role: .destructive) {
                            if let record = recordToDelete {
                                deleteRecord(record)
                            }
                        }
                    } message: {
                        Text("确定要删除这条记录吗？")
                    }
                }
                .padding(.vertical)
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
                // 设置初始值为当前记录值(如果有),否则使用默认值
                if let currentMax = exercise.maxRecord {
                    selectedValue = currentMax // 直接使用当前记录值作为初始值
                } else {
                    selectedValue = valueRange.first ?? 50.0 // 如果没有记录,使用范围的第一个值
                }
                loadRecords()
            }
            .overlay(
                ZStack {
                    if showSuccessAnimation {
                        Color.black.opacity(0.3)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            Text("保存成功")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            )
        }
    }
    
    private func log(_ message: String, type: String = "INFO") {
        let timestamp = Date().formatted(.dateTime.hour().minute().second())
        print("\n[\(type)] [\(timestamp)] 📝 \(message)")
    }
    
    private func saveRecord() {
        log("开始保存记录...")
        log("选择的数值: \(selectedValue)")
        
        guard !isLoading else {
            log("正在保存中,忽略重复请求", type: "WARN")
            return
        }
        isLoading = true
        
        let db = Firestore.firestore()
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            log("用户ID不存在", type: "ERROR")
            showError = true
            errorMessage = "用户ID不存在"
            isLoading = false
            return
        }
        log("用户ID: \(userId)")
        
        let now = Date()
        guard selectedValue > 0 else {
            log("无效的数值: \(selectedValue)", type: "ERROR")
            showError = true
            errorMessage = "请输入有效的数值"
            isLoading = false
            return
        }
        
        // 记录当前运动项目信息
        log("运动项目信息:")
        log("- 名称: \(exercise.name)")
        log("- 类别: \(exercise.category)")
        log("- 当前最大记录: \(exercise.maxRecord ?? 0)")
        
        let newRecord = ExerciseRecord(
            id: UUID().uuidString,
            value: selectedValue,
            date: now,
            isPR: exercise.maxRecord == nil || selectedValue > exercise.maxRecord!
        )
        
        log("新记录信息:")
        log("- ID: \(newRecord.id)")
        log("- 数值: \(newRecord.value)")
        log("- 是否为PR: \(newRecord.isPR)")
        
        let recordData: [String: Any] = [
            "id": newRecord.id,
            "value": Double(selectedValue),
            "date": Timestamp(date: now),
            "isPR": newRecord.isPR
        ]
        
        log("准备保存的数据: \(recordData)")
        
        let recordRef = db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
            .collection("records")
            .document(newRecord.id)
        
        log("开始写入数据库...")
        recordRef.setData(recordData) { error in
            if let error = error {
                log("保存失败: \(error.localizedDescription)", type: "ERROR")
                showError = true
                errorMessage = "保存失败: \(error.localizedDescription)"
                isLoading = false
                return
            }
            
            log("数据写入成功,开始验证...")
            recordRef.getDocument { (document, error) in
                if let error = error {
                    log("验证失败: \(error.localizedDescription)", type: "ERROR")
                } else if let savedData = document?.data() {
                    log("验证成功,保存的数据:")
                    savedData.forEach { key, value in
                        log("- \(key): \(value)")
                    }
                }
            }
            
            if newRecord.isPR {
                log("更新运动项目最大记录...")
                db.collection("users")
                    .document(userId)
                    .collection("exercises")
                    .document(exercise.id)
                    .updateData([
                        "maxRecord": Double(selectedValue),
                        "lastRecordDate": Timestamp(date: now)
                    ]) { error in
                        if let error = error {
                            log("更新最大记录失败: \(error.localizedDescription)", type: "ERROR")
                        } else {
                            log("最大记录更新成功")
                        }
                    }
            }
            
            log("播放成功反馈...")
            playSuccessSound()
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            log("显示成功动画...")
            withAnimation(.spring()) {
                showSuccessAnimation = true
                savedRecord = newRecord
                records.insert(newRecord, at: 0)
            }
            
            log("准备关闭页面...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    showSuccessAnimation = false
                    log("隐藏成功动画")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isLoading = false
                    log("保存流程完成,关闭页面")
                    dismiss()
                }
            }
        }
    }
    
    private func loadRecords() {
        log("开始加载历史记录...")
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            log("用户ID不存在", type: "ERROR")
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
            .collection("records")
            .order(by: "date", descending: true)
            .limit(to: 20)
            .getDocuments { snapshot, error in
                if let error = error {
                    log("加载失败: \(error.localizedDescription)", type: "ERROR")
                    showError = true
                    errorMessage = "加载失败: \(error.localizedDescription)"
                    return
                }
                
                log("获取到 \(snapshot?.documents.count ?? 0) 条记录")
                records = snapshot?.documents.compactMap { doc -> ExerciseRecord? in
                    let data = doc.data()
                    log("解析记录: \(data)")
                    
                    guard let value = data["value"] as? Double,
                          let date = (data["date"] as? Timestamp)?.dateValue(),
                          let isPR = data["isPR"] as? Bool
                    else {
                        log("记录数据格式错误: \(data)", type: "ERROR")
                        return nil
                    }
                    
                    return ExerciseRecord(
                        id: doc.documentID,
                        value: value,
                        date: date,
                        isPR: isPR
                    )
                } ?? []
                
                log("成功加载 \(records.count) 条记录")
            }
    }
    
    private func deleteRecord(_ record: ExerciseRecord) {
        log("开始删除记录...")
        log("记录ID: \(record.id)")
        
        // 添加删除振动反馈
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            log("用户ID不存在", type: "ERROR")
            return
        }
        
        let db = Firestore.firestore()
        let recordRef = db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
            .collection("records")
            .document(record.id)
        
        recordRef.delete { error in
            if let error = error {
                log("删除失败: \(error.localizedDescription)", type: "ERROR")
                showError = true
                errorMessage = "删除失败: \(error.localizedDescription)"
                return
            }
            
            log("记录删除成功")
            
            // 播放删除成功的触觉反馈
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // 显示删除成功动画
            withAnimation(.spring()) {
                showDeleteSuccessAnimation = true
                deletedRecordId = record.id
            }
            
            // 如果删除的是PR记录,需要更新最大记录
            if record.isPR {
                updateMaxRecordAfterDelete()
            }
            
            // 延迟移除记录
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    records.removeAll { $0.id == record.id }
                }
                
                // 更新外部状态
                onRecordUpdate?()
                
                // 隐藏成功动画
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        showDeleteSuccessAnimation = false
                        deletedRecordId = nil
                    }
                }
            }
        }
    }
    
    private func updateMaxRecordAfterDelete() {
        log("更新最大记录...")
        
        // 查找剩余记录中的最大值
        if let newMax = records.max(by: { $0.value < $1.value }) {
            let db = Firestore.firestore()
            guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
            
            let exerciseRef = db.collection("users")
                .document(userId)
                .collection("exercises")
                .document(exercise.id)
            
            exerciseRef.updateData([
                "maxRecord": newMax.value,
                "lastRecordDate": Timestamp(date: newMax.date)
            ]) { error in
                if let error = error {
                    log("更新最大记录失败: \(error.localizedDescription)", type: "ERROR")
                } else {
                    log("最大记录更新成功: \(newMax.value)")
                    // 重新加载历史最佳
                    exerciseRef.getDocument { (document, _) in
                        if document != nil {
                            DispatchQueue.main.async {
                                onRecordUpdate?()
                            }
                        }
                    }
                }
            }
        } else {
            // 如果没有剩余记录,清除最大记录
            let db = Firestore.firestore()
            guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
            
            db.collection("users")
                .document(userId)
                .collection("exercises")
                .document(exercise.id)
                .updateData([
                    "maxRecord": FieldValue.delete(),
                    "lastRecordDate": FieldValue.delete()
                ]) { error in
                    if error == nil {
                        onRecordUpdate?()
                    }
                }
        }
    }
    
    private func playSuccessSound() {
        AudioServicesPlaySystemSound(1004) // 使用更短的系统音效
    }
}

// 优化历史记录行视图
struct RecordRow: View {
    let record: ExerciseRecord
    let unit: String  // 添加单位参数
    let onDelete: () -> Void
    let isDeleting: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // 日期时间
            VStack(alignment: .leading, spacing: 4) {
                Text(record.date.formatted(.dateTime.month().day()))
                    .font(.system(size: 15, weight: .medium))
                Text(record.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(width: 60)
            
            // 分隔线
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 1, height: 30)
            
            // 记录值和单位
            HStack(spacing: 4) {
                Text("\(record.value, specifier: "%.1f")")
                    .font(.system(size: 17, weight: .medium))
                Text(unit)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // PR标志
            if record.isPR {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.yellow)
            }
            
            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        // 添加删除动画
        .opacity(isDeleting ? 0 : 1)
        .offset(x: isDeleting ? UIScreen.main.bounds.width : 0)
        .animation(.easeInOut(duration: 0.3), value: isDeleting)
    }
}

// 记录数据模型
struct ExerciseRecord: Identifiable {
    let id: String
    let value: Double
    let date: Date
    let isPR: Bool
} 