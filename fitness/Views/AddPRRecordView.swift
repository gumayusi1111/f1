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
    @State private var selectedIntegerPart: Int = 0
    @State private var selectedDecimalPart: Int = 0 // 0=0.00, 1=0.25, 2=0.50, 3=0.75
    var onRecordUpdate: (() -> Void)?
    
    // 修改滚轮选择器的范围计算
    private var valueRange: [Double] {
        // 如果当前项目有历史记录，使用80%-120%的范围
        if let currentMax = exercise.maxRecord {
            var values: [Double] = []
            let baseValue = Int(currentMax)
            let minValue = max(1, Int(Double(baseValue) * 0.8))
            let maxValue = Int(Double(baseValue) * 1.2)
            
            // 为每个整数添加0和0.5的小数部分
            for i in minValue...maxValue {
                values.append(Double(i))     // 整数.0
                values.append(Double(i) + 0.5) // 整数.5
            }
            return values
        } else {
            // 如果当前项目没有记录，使用默认范围
            var values: [Double] = []
            switch exercise.unit {
            case "次", "组":
                // 0-30的范围，每个整数都有.0和.5两个选项
                for i in 0...30 {
                    values.append(Double(i))
                    values.append(Double(i) + 0.5)
                }
            case "秒":
                // 0-60的范围
                for i in 0...60 {
                    values.append(Double(i))
                    values.append(Double(i) + 0.5)
                }
            // ... 其他单位的默认范围
            default:
                // 默认范围
                for i in 0...50 {
                    values.append(Double(i))
                    values.append(Double(i) + 0.5)
                }
            }
            return values
        }
    }

    // 修改整数范围计算
    private var integerRange: [Int] {
        // 如果当前项目有历史记录，使用80%-120%的范围
        if let currentMax = exercise.maxRecord {
            let baseValue = Int(currentMax)
            let minValue = max(1, Int(Double(baseValue) * 0.8))
            let maxValue = Int(Double(baseValue) * 1.2)
            return Array(minValue...maxValue)
        } else {
            // 如果当前项目没有记录，使用默认范围
            switch exercise.unit {
            case "次", "组":
                return Array(0...30)  // 0-30次/组
            case "秒":
                return Array(0...60)  // 0-60秒
            case "分钟":
                return Array(0...30)  // 0-30分钟
            case "kg", "lbs":
                return Array(0...100) // 0-100kg/lbs
            case "km", "mile":
                return Array(0...20)  // 0-20km/mile
            case "m":
                return Array(0...100) // 0-100m
            default:
                return Array(0...50)  // 默认范围
            }
        }
    }

    // 修改小数部分选项
    private var decimalParts: [Int] {
        switch exercise.unit {
        case "秒":
            return Array(0...9)  // 秒的小数部分0-9
        case "分钟":
            return Array(0...59) // 分钟的小数部分0-59秒
        case "m":
            return [0, 5]  // 米的小数部分只有0和5
        case "km", "mile":
            return [0, 25, 50, 75] // 公里和英里的小数部分
        default:
            return [0, 25, 50, 75] // 重量的小数部分
        }
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
                            if exercise.unit == "kg" || exercise.unit == "lbs" || 
                               exercise.unit == "秒" || exercise.unit == "分钟" || 
                               exercise.unit == "m" || exercise.unit == "km" || 
                               exercise.unit == "mile" {
                                // 整数部分选择器
                                Picker("整数", selection: $selectedIntegerPart) {
                                    ForEach(integerRange, id: \.self) { value in
                                        Text("\(value)").tag(value)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(width: 80, height: 120)
                                
                                Text(".")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                
                                // 小数部分选择器
                                Picker("小数", selection: $selectedDecimalPart) {
                                    ForEach(decimalParts, id: \.self) { value in
                                        Text(exercise.unit == "分钟" ? "\(value)秒" : "\(value)")
                                            .tag(value)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(width: exercise.unit == "分钟" ? 100 : 60, height: 120)
                                
                                Text(exercise.unit ?? "")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 8)
                            } else {
                                // 原有的其他单位选择器保持不变
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
                log("\n========== 视图加载 ==========")
                log("运动项目: \(exercise.name)")
                log("当前最大记录: \(exercise.maxRecord ?? 0)")
                
                // 设置初始值
                if let currentMax = exercise.maxRecord {
                    selectedValue = currentMax
                    selectedIntegerPart = Int(currentMax)
                    selectedDecimalPart = Int((currentMax.truncatingRemainder(dividingBy: 1)) * 100)
                    log("""
                        设置初始值:
                        - 整数部分: \(selectedIntegerPart)
                        - 小数部分: \(selectedDecimalPart)
                        - 完整值: \(selectedValue)
                        """)
                }
                
                log("开始加载记录...")
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
        log("运动项目: \(exercise.name)")
        log("当前最大记录: \(exercise.maxRecord ?? 0)")
        log("新记录值: \(selectedValue)")
        log("项目ID: \(exercise.id)")
        log("是否系统预设: \(exercise.isSystemPreset)")
        
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
        
        // 计算最终值
        let finalValue = if exercise.unit == "kg" || exercise.unit == "lbs" {
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 100.0
        } else if exercise.unit == "秒" {
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 10.0
        } else if exercise.unit == "分钟" {
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 60.0
        } else if exercise.unit == "m" {
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 10.0  // 0.5米 = 0.5
        } else if exercise.unit == "km" || exercise.unit == "mile" {
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 100.0  // 和重量单位一样的处理方式
        } else {
            selectedValue
        }
        
        // 创建记录
        let newRecord = ExerciseRecord(
            id: UUID().uuidString,
            value: finalValue,
            date: now,
            isPR: exercise.maxRecord == nil || finalValue > exercise.maxRecord!
        )
        
        log("新记录信息:")
        log("- ID: \(newRecord.id)")
        log("- 数值: \(newRecord.value)")
        log("- 是否为PR: \(newRecord.isPR)")
        
        // 保存到数据库
        let recordData: [String: Any] = [
            "id": newRecord.id,
            "value": Double(finalValue),
            "date": Timestamp(date: now),
            "isPR": newRecord.isPR
        ]
        
        log("准备保存的数据: \(recordData)")
        log("保存路径: users/\(userId)/exercises/\(exercise.id)/records/\(newRecord.id)")
        
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
                        "maxRecord": Double(finalValue),
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
                onRecordUpdate?()
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
        log("\n========== 开始加载记录 ==========")
        log("运动项目: \(exercise.name) (ID: \(exercise.id))")
        log("当前最大记录: \(exercise.maxRecord ?? 0) \(exercise.unit ?? "")")
        
        let db = Firestore.firestore()
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            log("❌ 用户ID不存在", type: "ERROR")
            return
        }
        log("用户ID: \(userId)")
        
        let recordsRef = db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
            .collection("records")
            .order(by: "date", descending: true)
        
        log("📝 开始查询记录: users/\(userId)/exercises/\(exercise.id)/records")
        
        recordsRef.getDocuments { snapshot, error in
            if let error = error {
                log("❌ 加载记录失败: \(error.localizedDescription)", type: "ERROR")
                return
            }
            
            log("📊 查询结果: 找到 \(snapshot?.documents.count ?? 0) 条记录")
            
            // 转换记录
            self.records = snapshot?.documents.compactMap { document in
                log("处理记录: \(document.documentID)")
                
                let data = document.data()  // 不需要 guard let，因为 data() 返回非可选类型
                
                // 详细记录每个字段的解析
                let id = data["id"] as? String
                let value = data["value"] as? Double
                let timestamp = data["date"] as? Timestamp
                let isPR = data["isPR"] as? Bool
                
                log("""
                    记录详情:
                    - ID: \(id ?? "nil")
                    - 值: \(value ?? 0)
                    - 时间戳: \(timestamp?.dateValue().description ?? "nil")
                    - 是否PR: \(isPR ?? false)
                    """)
                
                guard let id = id,
                      let value = value,
                      let date = timestamp?.dateValue(),
                      let isPR = isPR else {
                    log("❌ 记录数据格式错误: \(document.documentID)", type: "ERROR")
                    return nil
                }
                
                return ExerciseRecord(id: id, value: value, date: date, isPR: isPR)
            } ?? []
            
            log("✅ 成功加载并转换 \(self.records.count) 条记录")
            
            // 验证记录排序
            if !self.records.isEmpty {
                log("""
                    最新记录:
                    - 时间: \(self.records[0].date)
                    - 值: \(self.records[0].value)
                    - 是否PR: \(self.records[0].isPR)
                    """)
            }
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
        log("开始更新最大记录...")
        log("当前项目: \(exercise.name)")
        
        let db = Firestore.firestore()
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { 
            log("❌ 用户ID不存在", type: "ERROR")
            return 
        }
        
        // 先获取所有记录
        db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
            .collection("records")
            .order(by: "value", descending: true)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    log("❌ 获取记录失败: \(error.localizedDescription)", type: "ERROR")
                    return
                }
                
                if let maxRecord = snapshot?.documents.first {
                    // 找到新的最大值
                    if let newMaxValue = maxRecord.data()["value"] as? Double,
                       let date = (maxRecord.data()["date"] as? Timestamp)?.dateValue() {
                        log("✅ 找到新的最大记录: \(newMaxValue)")
                        
                        // 更新运动项目的最大记录
                        db.collection("users")
                            .document(userId)
                            .collection("exercises")
                            .document(exercise.id)
                            .updateData([
                                "maxRecord": newMaxValue,
                                "lastRecordDate": Timestamp(date: date)
                            ]) { error in
                                if let error = error {
                                    log("❌ 更新最大记录失败: \(error.localizedDescription)", type: "ERROR")
                                } else {
                                    log("✅ 最大记录已更新为: \(newMaxValue)")
                                    DispatchQueue.main.async {
                                        onRecordUpdate?()
                                    }
                                }
                            }
                    } else {
                        log("⚠️ 记录数据格式错误")
                    }
                } else {
                    // 如果没有记录了，清除最大记录
                    log("📝 没有找到任何记录，清除最大记录")
                    db.collection("users")
                        .document(userId)
                        .collection("exercises")
                        .document(exercise.id)
                        .updateData([
                            "maxRecord": FieldValue.delete(),
                            "lastRecordDate": FieldValue.delete()
                        ]) { error in
                            if let error = error {
                                log("❌ 清除最大记录失败: \(error.localizedDescription)", type: "ERROR")
                            } else {
                                log("✅ 已清除最大记录")
                                DispatchQueue.main.async {
                                    onRecordUpdate?()
                                }
                            }
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