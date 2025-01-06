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
    @State private var currentPage = 0
    @State private var recordsPerPage = 8
    @State private var pageTransition: Double = 0 // 控制翻页动画方向
    @State private var expandTransition: Bool = false // 控制展开/收起动画
    @State private var isLoadingRecords = false
    @State private var lastLoadTime: Date?
    private let cacheExpirationInterval: TimeInterval = 300 // 缓存5分钟过期
    @State private var lastDocument: DocumentSnapshot? // 用于分页
    @State private var isLoadingMore = false // 是否正在加载更多
    @State private var hasMoreRecords = true // 是否还有更多记录
    private let pageSize = 10 // 每页加载记录数
    var onRecordUpdate: (() -> Void)?
    private let cacheVersion = 1  // 缓存版本号
    private let maxCacheAge: TimeInterval = 24 * 60 * 60  // 缓存最大保存时间(24小时)
    private let maxCacheRecords = 100  // 最大缓存记录数
    private let minCacheInterval: TimeInterval = 60  // 最小缓存更新间隔(1分钟)
    
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
                                        Text(getDecimalText(value: value))
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
                    
                    // 使用新的进步图表
                    ExerciseProgressChart(records: records, unit: exercise.unit ?? "")
                    
                    // 历史记录列表
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("历史记录")
                                .font(.headline)
                            Spacer()
                            if !records.isEmpty {
                                Button(action: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        expandTransition.toggle()
                                        isHistoryExpanded.toggle()
                                        if !isHistoryExpanded {
                                            currentPage = 0
                                        }
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Text(isHistoryExpanded ? "收起" : "展开")
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                        Image(systemName: isHistoryExpanded ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 12))
                                            .foregroundColor(.blue)
                                            .rotationEffect(.degrees(expandTransition ? 180 : 0))
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
                        } else if isHistoryExpanded {
                            VStack(spacing: 12) {
                                let startIndex = currentPage * recordsPerPage
                                let endIndex = min(startIndex + recordsPerPage, records.count)
                                let displayedRecords = Array(records[startIndex..<endIndex])
                                
                                // 记录列表容器
                                VStack(spacing: 12) {
                                    ForEach(displayedRecords) { record in
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
                                            insertion: .move(edge: pageTransition > 0 ? .trailing : .leading)
                                                .combined(with: .opacity),
                                            removal: .move(edge: pageTransition > 0 ? .leading : .trailing)
                                                .combined(with: .opacity)
                                        ))
                                    }
                                }
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentPage)
                                
                                // 分页控制
                                if records.count > recordsPerPage {
                                    HStack(spacing: 20) {
                                        Button(action: {
                                            pageTransition = -1
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                currentPage = max(0, currentPage - 1)
                                            }
                                        }) {
                                            Image(systemName: "chevron.left")
                                                .font(.system(size: 16, weight: .semibold))
                                        }
                                        .disabled(currentPage == 0)
                                        .opacity(currentPage == 0 ? 0.5 : 1)
                                        
                                        Text("\(currentPage + 1) / \(Int(ceil(Double(records.count) / Double(recordsPerPage))))")
                                            .font(.subheadline)
                                            .transition(.opacity)
                                        
                                        Button(action: {
                                            pageTransition = 1
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                currentPage = min(currentPage + 1, (records.count - 1) / recordsPerPage)
                                            }
                                        }) {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 16, weight: .semibold))
                                        }
                                        .disabled(currentPage >= (records.count - 1) / recordsPerPage)
                                        .opacity(currentPage >= (records.count - 1) / recordsPerPage ? 0.5 : 1)
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.top, 8)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
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
        log("选择的整数部分: \(selectedIntegerPart)")
        log("选择的小数部分: \(selectedDecimalPart)")
        
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
        
        // 计算最终值
        let finalValue = if exercise.unit == "kg" || exercise.unit == "lbs" {
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 100.0
        } else if exercise.unit == "秒" {
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 10.0
        } else if exercise.unit == "分钟" {
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 60.0
        } else if exercise.unit == "m" {
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 10.0
        } else if exercise.unit == "km" || exercise.unit == "mile" {
            Double(selectedIntegerPart) + Double(selectedDecimalPart) / 100.0
        } else {
            selectedValue
        }
        
        log("计算得到的最终值: \(finalValue)")
        
        // 验证最终值
        guard finalValue > 0 else {
            log("无效的最终值: \(finalValue)", type: "ERROR")
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
        
        // 创建记录
        let newRecord = ExerciseRecord(
            id: UUID().uuidString,
            value: finalValue,
            date: Date(),
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
            "date": Timestamp(date: Date()),
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
                        "lastRecordDate": Timestamp(date: Date())
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
                saveRecordsToCache(records)
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
    
    private func loadRecords(forceRefresh: Bool = false) {
        guard !isLoadingRecords else { return }
        
        log("\n========== 开始加载记录 ==========")
        log("强制刷新: \(forceRefresh)")
        
        // 如果是强制刷新,重置分页状态
        if forceRefresh {
            lastDocument = nil
            records = []
            hasMoreRecords = true
        }
        
        // 检查缓存
        if !forceRefresh,
           let lastLoad = lastLoadTime,
           Date().timeIntervalSince(lastLoad) < cacheExpirationInterval,
           let cachedRecords = loadRecordsFromCache() {
            log("📦 使用缓存数据: \(cachedRecords.count) 条记录")
            self.records = cachedRecords
            return
        }
        
        isLoadingRecords = true
        log("运动项目: \(exercise.name) (ID: \(exercise.id))")
        
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            log("❌ 用户ID不存在", type: "ERROR")
            isLoadingRecords = false
            return
        }
        
        var query = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
            .collection("records")
            .order(by: "date", descending: true)
            .limit(to: pageSize)
        
        // 如果有上一页的最后一条记录,从那里开始查询
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        log("📝 查询参数:")
        log("- 页大小: \(pageSize)")
        log("- 是否有上一页: \(lastDocument != nil)")
        
        query.getDocuments { snapshot, error in
            defer { self.isLoadingRecords = false }
            
            if let error = error {
                log("❌ 加载失败: \(error.localizedDescription)", type: "ERROR")
                return
            }
            
            guard let snapshot = snapshot else {
                log("❌ 未获取到数据", type: "ERROR")
                return
            }
            
            log("📊 本次查询结果: \(snapshot.documents.count) 条记录")
            
            // 更新是否还有更多记录
            self.hasMoreRecords = snapshot.documents.count == self.pageSize
            log("是否还有更多记录: \(self.hasMoreRecords)")
            
            // 保存最后一条记录用于下次查询
            self.lastDocument = snapshot.documents.last
            
            // 转换记录
            let newRecords = snapshot.documents.compactMap { document -> ExerciseRecord? in
                let data = document.data()
                guard let id = data["id"] as? String,
                      let value = data["value"] as? Double,
                      let date = (data["date"] as? Timestamp)?.dateValue(),
                      let isPR = data["isPR"] as? Bool else {
                    log("❌ 记录格式错误: \(document.documentID)", type: "ERROR")
                    return nil
                }
                return ExerciseRecord(id: id, value: value, date: date, isPR: isPR)
            }
            
            log("✅ 成功转换 \(newRecords.count) 条记录")
            
            // 如果是刷新,替换全部记录;否则追加新记录
            if forceRefresh {
                self.records = newRecords
            } else {
                self.records.append(contentsOf: newRecords)
            }
            
            // 保存到缓存
            self.saveRecordsToCache(self.records)
            log("💾 已更新缓存,当前总记录数: \(self.records.count)")
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
                    saveRecordsToCache(records)
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
    
    private func getDecimalText(value: Int) -> String {
        if exercise.unit == "分钟" {
            return "\(value)秒"
        } else if exercise.unit == "kg" || exercise.unit == "lbs" || 
                  exercise.unit == "km" || exercise.unit == "mile" {
            // 对于使用 25/50/75 格式的单位，0 显示为 "00"
            return value == 0 ? "00" : "\(value)"
        } else {
            // 对于其他单位（秒、米等），保持原样显示
            return "\(value)"
        }
    }
    
    private func getCacheKey(for exerciseId: String) -> String {
        return "exercise_records_v\(cacheVersion)_\(exerciseId)"
    }
    
    private struct CacheMetadata: Codable {
        let version: Int
        let timestamp: Date
        let recordCount: Int
    }
    
    private func loadRecordsFromCache() -> [ExerciseRecord]? {
        let cacheKey = getCacheKey(for: exercise.id)
        let metadataKey = "\(cacheKey)_metadata"
        
        log("\n========== 读取缓存 ==========")
        
        // 检查缓存元数据
        guard let metadataData = UserDefaults.standard.data(forKey: metadataKey),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData) else {
            log("❌ 未找到缓存元数据")
            return nil
        }
        
        // 验证缓存版本
        guard metadata.version == cacheVersion else {
            log("❌ 缓存版本不匹配")
            clearCache()
            return nil
        }
        
        // 检查缓存是否过期
        let cacheAge = Date().timeIntervalSince(metadata.timestamp)
        if cacheAge > maxCacheAge {
            log("❌ 缓存已过期 (年龄: \(Int(cacheAge/3600))小时)")
            clearCache()
            return nil
        }
        
        // 读取缓存数据
        guard let cachedData = UserDefaults.standard.data(forKey: cacheKey),
              let cachedRecords = try? JSONDecoder().decode([ExerciseRecord].self, from: cachedData) else {
            log("❌ 缓存数据读取失败")
            return nil
        }
        
        log("""
            ✅ 成功读取缓存:
            - 版本: v\(metadata.version)
            - 年龄: \(Int(cacheAge/60))分钟
            - 记录数: \(cachedRecords.count)
            """)
        
        return cachedRecords
    }
    
    private func saveRecordsToCache(_ records: [ExerciseRecord]) {
        let cacheKey = getCacheKey(for: exercise.id)
        let metadataKey = "\(cacheKey)_metadata"
        
        // 检查是否需要更新缓存
        if let lastUpdate = lastLoadTime,
           Date().timeIntervalSince(lastUpdate) < minCacheInterval {
            log("⏳ 缓存更新间隔太短，跳过")
            return
        }
        
        // 限制缓存记录数量并转换为数组
        let recordsToCache = Array(records.prefix(maxCacheRecords))
        
        // 保存记录数据
        guard let encodedData = try? JSONEncoder().encode(recordsToCache) else {
            log("❌ 记录编码失败")
            return
        }
        
        // 保存元数据
        let metadata = CacheMetadata(
            version: cacheVersion,
            timestamp: Date(),
            recordCount: recordsToCache.count
        )
        
        guard let metadataData = try? JSONEncoder().encode(metadata) else {
            log("❌ 元数据编码失败")
            return
        }
        
        // 写入缓存
        UserDefaults.standard.set(encodedData, forKey: cacheKey)
        UserDefaults.standard.set(metadataData, forKey: metadataKey)
        lastLoadTime = Date()
        
        log("""
            💾 缓存更新成功:
            - 记录数: \(recordsToCache.count)
            - 数据大小: \(ByteCountFormatter.string(fromByteCount: Int64(encodedData.count), countStyle: .file))
            """)
    }
    
    private func clearCache() {
        let cacheKey = getCacheKey(for: exercise.id)
        let metadataKey = "\(cacheKey)_metadata"
        
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: metadataKey)
        
        log("🧹 缓存已清理")
    }
    
    // 添加加载更多函数
    private func loadMoreRecords() {
        guard hasMoreRecords && !isLoadingRecords else { return }
        log("\n========== 加载更多记录 ==========")
        loadRecords()
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
struct ExerciseRecord: Identifiable, Codable {
    let id: String
    let value: Double
    let date: Date
    let isPR: Bool
} 