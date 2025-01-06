import SwiftUI
import FirebaseFirestore
import AudioToolbox

// 添加在文件顶部
private func getCategoryColor(_ category: String) -> Color {
    switch category {
    case "胸部":
        return .red
    case "背部":
        return .blue
    case "腿部":
        return .purple
    case "肩部":
        return .orange
    case "手臂":
        return .green
    case "核心":
        return .pink
    case "有氧":
        return .cyan
    default:
        return .blue
    }
}

// 1. 添加 AlertType 枚举定义
enum AlertType {
    case deleteConfirm(exercise: Exercise?)
    case limitReached
    case deleteLimit
}

// 使用新的组件
struct MaxRecordsView: View {
    @AppStorage("userId") private var userId: String = ""
    @State private var exercises: [Exercise] = []
    @State private var showingProjectSheet = false
    @State private var showingAddSheet = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var showSystemExercises = false
    @State private var showCustomExercises = false
    @AppStorage("lastSyncDate") private var lastSyncDate: Date = .distantPast
    @State private var prSearchText = ""
    @State private var selectedPRCategory: String?
    @State private var recentPRs: [Exercise] = []  // 最近的PR记录
    @StateObject private var connectivityManager = ConnectivityManager()
    @State private var isRefreshing = false
    @State private var isFirstLoading = true  // 用于首次加载显示骨架屏
    
    // 刷新相关状态
    @State private var lastRefreshTime: Date = UserDefaults.standard.object(forKey: "lastRefreshTime") as? Date ?? .distantPast
    @State private var showRefreshLimitAlert = false
    @State private var lastSyncTimeString: String = "未同步"
    
    // 所有可用的运动类别
    private let categories = ["全部", "胸部", "背部", "腿部", "肩部", "手臂", "核心", "有氧"]
    
    private let prColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    @State private var currentPage = 1
    private let pageSize = 6
    
    // 计算总页数
    private var totalPages: Int {
        let total = Int(ceil(Double(filteredPRs.count) / Double(pageSize)))
        return max(1, total)  // 确保至少有一页
    }
    
    // 获取当前页的项目
    private var currentPageItems: [Exercise] {
        guard !filteredPRs.isEmpty else { return [] }  // 如果没有数据，返回空数组
        
        let startIndex = (currentPage - 1) * pageSize
        // 确保 startIndex 不超过数组长度
        guard startIndex < filteredPRs.count else { 
            currentPage = 1  // 重置到第一页
            return Array(filteredPRs[0..<min(pageSize, filteredPRs.count)])
        }
        
        let endIndex = min(startIndex + pageSize, filteredPRs.count)
        return Array(filteredPRs[startIndex..<endIndex])
    }
    
    // 添加页码验证函数
    private func validateCurrentPage() {
        if currentPage > totalPages {
            currentPage = totalPages
        }
        if currentPage < 1 {
            currentPage = 1
        }
    }
    
    // 1. 添加缓存键常量
    private let PR_CACHE_KEY = "cachedPRRecords"
    
    // 在 MaxRecordsView 中添加状态来追踪 sheet 的显示
    @State private var isSheetPresented = false
    
    // 添加一个新的 State 属性来控制 ScrollView
    @State private var scrollProxy: ScrollViewProxy?
    
    init() {
        // 确保只在首次加载时初始化
        if UserDefaults.standard.bool(forKey: "firestoreInitialized") == false {
            setupFirestore()
        }
    }
    
    private func setupFirestore() {
        // 只在第一次初始化时设置缓存
        if UserDefaults.standard.bool(forKey: "firestoreInitialized") == false {
            let db = Firestore.firestore()
            let settings = FirestoreSettings()
            settings.cacheSettings = PersistentCacheSettings()
            db.settings = settings
            
            // 标记已初始化
            UserDefaults.standard.set(true, forKey: "firestoreInitialized")
        }
    }
    
    // 检查是否可以刷新
    private func canRefresh() -> Bool {
        guard let lastRefresh = UserDefaults.standard.object(forKey: "lastRefreshTime") as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastRefresh) >= 60
    }
    
    // 更新最后刷新时间
    private func updateLastRefreshTime() {
        let now = Date()
        UserDefaults.standard.set(now, forKey: "lastRefreshTime")
        lastRefreshTime = now
    }
    
    // 1. 添加 updateLastSyncTime 函数
    private func updateLastSyncTime() {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        
        if lastSyncDate == .distantPast {
            lastSyncTimeString = "未同步"
            print("⚠️ 同步状态: 未同步")
        } else {
            lastSyncTimeString = formatter.localizedString(for: lastSyncDate, relativeTo: Date())
            print("📅 更新同步时间: \(lastSyncTimeString)")
        }
    }
    
    // 添加一个一次性清理函数
    private func cleanupDuplicateSystemExercises() async {
        print("\n========== 开始清理重复的系统预设项目 ==========")
        let db = Firestore.firestore()
        
        do {
            // 1. 获取系统预设ID列表
            let systemSnapshot = try await db.collection("systemExercises").getDocuments()
            let systemIds = Set(systemSnapshot.documents.map { $0.documentID })
            print("📊 系统预设项目数量：\(systemIds.count)")
            
            // 2. 获取用户项目列表
            let userSnapshot = try await db.collection("users")
                .document(userId)
                .collection("exercises")
                .getDocuments()
            
            // 3. 找出需要删除的文档
            var documentsToDelete: [String] = []
            for doc in userSnapshot.documents {
                if systemIds.contains(doc.documentID) {
                    documentsToDelete.append(doc.documentID)
                    print("🗑️ 将删除重复项目：\(doc.data()["name"] ?? "未知") (ID: \(doc.documentID))")
                }
            }
            
            print("\n开始删除 \(documentsToDelete.count) 个重复项目...")
            
            // 4. 批量删除重复项目
            let batch = db.batch()
            for docId in documentsToDelete {
                let docRef = db.collection("users")
                    .document(userId)
                    .collection("exercises")
                    .document(docId)
                batch.deleteDocument(docRef)
            }
            
            try await batch.commit()
            print("✅ 成功删除 \(documentsToDelete.count) 个重复项目")
            
            // 5. 验证清理结果
            let finalSnapshot = try await db.collection("users")
                .document(userId)
                .collection("exercises")
                .getDocuments()
            
            print("\n清理结果：")
            print("原始项目数量：\(userSnapshot.documents.count)")
            print("删除项目数量：\(documentsToDelete.count)")
            print("剩余项目数量：\(finalSnapshot.documents.count)")
            
            print("\n========== 清理完成 ==========")
            
        } catch {
            print("❌ 清理失败：\(error.localizedDescription)")
        }
    }
    
    // 2. 修改 performRefresh 函数
    private func performRefresh() async {
        guard !isRefreshing else { return }
        
        if !canRefresh() {
            showRefreshLimitAlert = true
            isRefreshing = false
            return
        }
        
        print("\n========== 开始刷新数据 ==========")
        print("📱 开始刷新: \(Date())")
        
        isRefreshing = true
        
        do {
            // 1. 优先刷新有记录的项目
            let priorityRecords = recentPRs.filter { $0.maxRecord != nil }
            if !priorityRecords.isEmpty {
                print("🔄 优先刷新 \(priorityRecords.count) 个有记录的项目")
                
                // 只刷新第一页的有记录项目
                let firstPageCount = min(pageSize, priorityRecords.count)
                let priorityFirstPage = Array(priorityRecords[0..<firstPageCount])
                
                // 异步更新这些记录
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for exercise in priorityFirstPage {
                        group.addTask {
                            try await updateExerciseRecord(exercise)
                        }
                    }
                    try await group.waitForAll()
                }
                
                // 立即更新UI显示第一页的更新结果
                DispatchQueue.main.async {
                    currentPage = 1 // 确保显示第一页
                    // 触发 filteredPRs 重新计算
                    self.recentPRs = self.recentPRs
                }
            }
            
            // 2. 后台继续加载其他数据
            Task {
                try await loadExercises()
                try await loadRecentPRs()
                
                // 更新刷新时间和同步状态
                updateLastRefreshTime()
                lastSyncDate = Date()
                updateLastSyncTime()
                
                print("✅ 数据刷新成功")
                print("📅 最后同步时间: \(lastSyncTimeString)")
            }
            
        } catch {
            print("❌ 刷新失败: \(error.localizedDescription)")
        }
        
        // 确保在所有情况下都会重置刷新状态
        DispatchQueue.main.async {
            isRefreshing = false
        }
        
        print("========== 刷新结束 ==========\n")
    }
    
    @MainActor
    private func updateExerciseRecord(_ exercise: Exercise) async throws {
        print("\n========== 开始更新运动记录 ==========")
        print("📝 运动项目: \(exercise.name)")
        print("📝 当前最大记录: \(exercise.maxRecord ?? 0)")
        
        let db = Firestore.firestore()
        let docRef = db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
        
        // 获取运动记录
        let recordsRef = docRef.collection("records")
        let records = try await recordsRef.order(by: "value", descending: true).limit(to: 1).getDocuments()
        
        print("📝 查询到的记录数: \(records.documents.count)")
        
        if let record = records.documents.first,
           let value = record.data()["value"] as? Double {
            print("📝 找到最大记录: \(value)")
            
            // 1. 更新 Firestore
            let data: [String: Any] = [
                "maxRecord": value,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await docRef.updateData(data)
            print("✅ Firestore 更新成功")
            
            // 2. 更新本地数据
            if let index = self.recentPRs.firstIndex(where: { $0.id == exercise.id }) {
                print("📝 更新本地数据 index: \(index)")
                let updatedExercise = Exercise(
                    id: exercise.id,
                    name: exercise.name,
                    category: exercise.category,
                    description: exercise.description,
                    notes: exercise.notes,
                    isSystemPreset: exercise.isSystemPreset,
                    unit: exercise.unit,
                    createdAt: exercise.createdAt,
                    updatedAt: Date(),
                    maxRecord: value,
                    lastRecordDate: exercise.lastRecordDate
                )
                
                // 3. 强制刷新整个数组
                var newPRs = self.recentPRs
                newPRs[index] = updatedExercise
                self.recentPRs = newPRs
                
                print("📝 本地数据更新完成，新记录: \(value)")
            }
        }
        
        print("========== 更新完成 ==========\n")
    }
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // 添加一个带 id 的空 View 作为滚动目标
                        Color.clear
                            .frame(height: 0)
                            .id("top")
                        
                        // 同步状态指示器
                        HStack {
                            Text(lastSyncTimeString == "未同步" ? "下拉刷新" : "上次同步：\(lastSyncTimeString)")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            
                            if isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .padding(.top, 10)
                        
                        // 主要内容
                        VStack(spacing: 20) {
                            // 项目管理入口
                            Button(action: { showingProjectSheet = true }) {
                                // 整个卡片容器
                                HStack(spacing: 15) {
                                    // 左侧图标
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.1))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "dumbbell.fill")
                                            .foregroundColor(.blue)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("项目管理")
                                            .font(.headline)
                                        Text("管理训练项目和动作")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                                )
                            }
                            .padding(.horizontal)
                            
                            // PR 搜索栏
                            SearchBar(text: $prSearchText)
                                .padding(.horizontal)
                            
                            // PR 类别选择
                            ScrollView(.horizontal, showsIndicators: false) {
                                VStack(spacing: 0) {
                                    HStack(spacing: 12) {
                                        ForEach(categories, id: \.self) { category in
                                            let count = category == "全部" ? 
                                                (prSearchText.isEmpty ? recentPRs.count : filteredPRs.count) :
                                                recentPRs.filter { exercise in
                                                    let matchesCategory = exercise.category == category
                                                    let matchesSearch = prSearchText.isEmpty || 
                                                        exercise.name.localizedCaseInsensitiveContains(prSearchText)
                                                    return matchesCategory && matchesSearch
                                                }.count
                                            
                                            Button(action: { 
                                                // 添加触觉反馈
                                                let generator = UIImpactFeedbackGenerator(style: .light)
                                                generator.prepare()
                                                generator.impactOccurred()
                                                
                                                // 播放系统音效
                                                AudioServicesPlaySystemSound(1104)
                                                
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    selectedPRCategory = category
                                                }
                                            }) {
                                                VStack(spacing: 8) {
                                                    HStack(spacing: 4) {
                                                        Text(category)
                                                        Text("\(count)")
                                                            .font(.system(size: 12))
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(
                                                                Capsule()
                                                                    .fill(selectedPRCategory == category ? 
                                                                        Color.white.opacity(0.2) : 
                                                                        getCategoryColor(category).opacity(0.1))
                                                            )
                                                    }
                                                    .font(.system(size: 14))
                                                    .fontWeight(selectedPRCategory == category ? .semibold : .regular)
                                                    .foregroundColor(selectedPRCategory == category ? .white : .primary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(selectedPRCategory == category ? 
                                                                getCategoryColor(category) : Color(.systemGray6))
                                                    )
                                                    
                                                    // 添加下划线
                                                    Rectangle()
                                                        .fill(getCategoryColor(category))
                                                        .frame(height: 2)
                                                        .opacity(selectedPRCategory == category ? 1 : 0)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            
                            // PR 记录展示
                            VStack(spacing: 16) {
                                if isFirstLoading {
                                    // 骨架屏
                                    LazyVGrid(columns: prColumns, spacing: 16) {
                                        ForEach(0..<6, id: \.self) { _ in
                                            PRRecordCardSkeleton()
                                        }
                                    }
                                    .padding(.horizontal)
                                } else {
                                    LazyVGrid(columns: prColumns, spacing: 16) {
                                        ForEach(currentPageItems) { exercise in
                                            PRRecordCard(
                                                exercise: exercise,
                                                maxRecord: exercise.maxRecord,
                                                lastRecordDate: exercise.lastRecordDate
                                            )
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                
                                // 分页控制
                                if !filteredPRs.isEmpty {  // 修改这里，只要有数据就显示分页
                                    HStack(spacing: 20) {
                                        Button(action: {
                                            // 添加触觉反馈
                                            let generator = UIImpactFeedbackGenerator(style: .light)
                                            generator.prepare()
                                            generator.impactOccurred()
                                            
                                            withAnimation {
                                                currentPage = max(1, currentPage - 1)
                                            }
                                        }) {
                                            Image(systemName: "chevron.left")
                                                .foregroundColor(currentPage > 1 ? .blue : .gray)
                                        }
                                        .disabled(currentPage <= 1)
                                        
                                        Text("\(currentPage) / \(totalPages)")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                        
                                        Button(action: {
                                            // 添加触觉反馈
                                            let generator = UIImpactFeedbackGenerator(style: .light)
                                            generator.prepare()
                                            generator.impactOccurred()
                                            
                                            withAnimation {
                                                currentPage = min(totalPages, currentPage + 1)
                                            }
                                        }) {
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(currentPage < totalPages ? .blue : .gray)
                                        }
                                        .disabled(currentPage >= totalPages)
                                    }
                                    .padding(.bottom)
                                }
                            }
                        }
                    }
                    // 将 onAppear 移到这里
                    .onAppear {
                        scrollProxy = proxy
                    }
                }
                .refreshable {
                    await performRefresh()
                }
                .alert("刷新限制", isPresented: $showRefreshLimitAlert) {
                    Button("知道了", role: .cancel) {
                        // 在弹窗关闭时强制滚动到顶部
                        withAnimation(.spring()) {
                            scrollProxy?.scrollTo("top", anchor: .top)
                            isRefreshing = false
                        }
                    }
                } message: {
                    Text("请等待一分钟后再次刷新")
                }
            }
            .overlay(
                VStack {
                    if !connectivityManager.isOnline {
                        Text("网络连接已断开")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                    }
                    Spacer()
                }
                .padding(.top)
            )
            .onAppear {
                updateLastSyncTime() // 只更新同步时间显示
                
                // 如果是首次加载，尝试从缓存加载数据
                if isFirstLoading {
                    Task {
                        if let cached = loadPRsFromCache() {
                            withAnimation {
                                self.recentPRs = cached
                                isFirstLoading = false
                            }
                            print("✅ 从缓存加载了 \(cached.count) 条PR记录")
                        }
                        
                        // 尝试从缓存加载运动项目
                        if let cached = loadFromCache() {
                            print("📦 从缓存加载数据...")
                            self.exercises = cached
                            isLoading = false
                            print("✅ 从缓存加载了 \(cached.count) 个项目")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingProjectSheet) {
            isSheetPresented = false // sheet 关闭时更新状态
        } content: {
            ProjectManagementSheet(
                exercises: $exercises,
                showSystemExercises: $showSystemExercises,
                showCustomExercises: $showCustomExercises
            )
            .onAppear {
                isSheetPresented = true // sheet 显示时更新状态
            }
        }
    }
    
    // 修改 filteredPRs 计算属性
    private var filteredPRs: [Exercise] {
        // 1. 先按照搜索和类别过滤
        let filtered = recentPRs.filter { exercise in
            let matchesSearch = prSearchText.isEmpty || 
                exercise.name.localizedCaseInsensitiveContains(prSearchText)
            
            let matchesCategory = selectedPRCategory == nil || 
                selectedPRCategory == "全部" || 
                exercise.category == selectedPRCategory
            
            return matchesSearch && matchesCategory
        }
        
        // 2. 按照记录排序
        return filtered.sorted { first, second in
            // 如果第一个有记录而第二个没有，第一个排在前面
            if first.maxRecord != nil && second.maxRecord == nil {
                return true
            }
            // 如果第一个没有记录而第二个有，第二个排在前面
            if first.maxRecord == nil && second.maxRecord != nil {
                return false
            }
            // 如果都有记录，根据运动类型比较
            if let firstRecord = first.maxRecord,
               let secondRecord = second.maxRecord {
                
                // 核心类别的时间越长越好
                if first.category == "核心" && second.category == "核心" {
                    return firstRecord > secondRecord
                }
                
                // 有氧类别（除了核心）时间越短越好
                if first.category == "有氧" && second.category == "有氧" {
                    return firstRecord < secondRecord
                }
                
                // 其他类别（重量、次数等）越大越好
                return firstRecord > secondRecord
            }
            
            // 如果都没有记录，按名称排序
            return first.name < second.name
        }
    }
    
    // 修改加载 PR 记录的函数
    private func loadRecentPRs() async throws {
        print("📱 开始加载PR记录...")
        isFirstLoading = true
        
        // 1. 先尝试从缓存加载
        if let cached = loadPRsFromCache() {
            withAnimation {
                self.recentPRs = cached
                isFirstLoading = false
            }
            print("✅ 从缓存加载了 \(cached.count) 条PR记录")
            
            // 如果不是在刷新状态，就直接返回
            if !isRefreshing {
                return
            }
        }
        
        // 2. 检查网络状态
        guard connectivityManager.isOnline else {
            print("⚠️ 离线状态，使用缓存数据")
            isFirstLoading = false
            return
        }
        
        print("🔄 正在从服务器获取最新数据...")
        
        return try await withCheckedThrowingContinuation { continuation in
            let db = Firestore.firestore()
            db.collection("users")
                .document(userId)
                .collection("exercises")
                .order(by: "updatedAt", descending: true)
                .getDocuments { [self] snapshot, error in
                    if let error = error {
                        print("❌ 加载PR记录失败: \(error.localizedDescription)")
                        isFirstLoading = false
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    if let documents = snapshot?.documents {
                        var records = documents.compactMap { document in
                            try? document.data(as: Exercise.self)
                        }
                        
                        // 加载系统预设项目
                        db.collection("systemExercises")
                            .getDocuments { snapshot, error in
                                if let error = error {
                                    print("❌ 加载系统预设失败: \(error.localizedDescription)")
                                    continuation.resume(throwing: error)
                                    return
                                }
                                
                                if let documents = snapshot?.documents {
                                    let systemRecords = documents.compactMap { document in
                                        try? document.data(as: Exercise.self)
                                    }
                                    records.append(contentsOf: systemRecords)
                                    
                                    withAnimation {
                                        self.recentPRs = records
                                        isFirstLoading = false
                                    }
                                    
                                    // 保存到缓存
                                    self.savePRsToCache(records)
                                    
                                    print("✅ 成功加载 \(records.count) 条PR记录（包含 \(systemRecords.count) 条系统记录）")
                                    continuation.resume(returning: ())
                                } else {
                                    print("⚠️ 没有找到系统预设记录")
                                    continuation.resume(returning: ())
                                }
                            }
                    } else {
                        print("⚠️ 没有找到PR记录")
                        isFirstLoading = false
                        continuation.resume(returning: ())
                    }
                }
        }
    }
    
    // 3. 添加缓存相关函数
    private func loadPRsFromCache() -> [Exercise]? {
        if let data = UserDefaults.standard.data(forKey: PR_CACHE_KEY),
           let cached = try? JSONDecoder().decode([Exercise].self, from: data) {
            return cached
        }
        return nil
    }
    
    private func savePRsToCache(_ records: [Exercise]) {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: PR_CACHE_KEY)
            print("✅ 保存了 \(records.count) 条PR记录到缓存")
        }
    }
    
    private func loadFromCache() -> [Exercise]? {
        if let data = UserDefaults.standard.data(forKey: "cachedExercises"),
           let cached = try? JSONDecoder().decode([Exercise].self, from: data) {
            print("✅ 从缓存加载了 \(cached.count) 个项目")
            return cached
        }
        return nil
    }
    
    private func saveToCache(_ exercises: [Exercise]) {
        if let encoded = try? JSONEncoder().encode(exercises) {
            UserDefaults.standard.set(encoded, forKey: "cachedExercises")
            print("✅ 保存了 \(exercises.count) 个项目到缓存")
        }
    }
    
    // 修改为异步函数
    private func loadExercises() async throws {
        print("\n========== 开始加载运动项目 ==========")
        isLoading = true
        
        // 1. 缓存检查
        print("\n----- 检查缓存 -----")
        if let cached = loadFromCache() {
            print("📦 从缓存加载数据：\(cached.count) 个项目")
            print("系统预设：\(cached.filter { $0.isSystemPreset }.count) 个")
            print("用户自定义：\(cached.filter { !$0.isSystemPreset }.count) 个")
            
            self.exercises = cached
            isLoading = false
            
            if !isRefreshing {
                print("✅ 使用缓存数据，跳过服务器请求")
                return
            }
        } else {
            print("⚠️ 未找到缓存数据")
        }
        
        // 2. 网络检查
        guard connectivityManager.isOnline else {
            print("❌ 离线状态，无法从服务器加载")
            isLoading = false
            return
        }
        
        // 3. 加载系统预设
        print("\n----- 加载系统预设项目 -----")
        let db = Firestore.firestore()
        let systemSnapshot = try await db.collection("systemExercises").getDocuments()
        
        print("📊 系统预设文档数量：\(systemSnapshot.documents.count)")
        print("\n系统预设详细信息：")
        for doc in systemSnapshot.documents {
            print("ID: \(doc.documentID)")
            print("名称: \(doc.data()["name"] ?? "未知")")
            print("类别: \(doc.data()["category"] ?? "未知")")
            print("系统预设标志: \(doc.data()["isSystemPreset"] ?? "未知")")
            print("---")
        }
        
        var allExercises: [Exercise] = []
        var systemIds = Set<String>()  // 用于追踪系统预设ID
        
        // 处理系统预设
        for doc in systemSnapshot.documents {
            if let exercise = Exercise(dictionary: doc.data(), id: doc.documentID) {
                var systemExercise = exercise
                systemExercise.isSystemPreset = true
                allExercises.append(systemExercise)
                systemIds.insert(doc.documentID)  // 记录系统预设ID
            } else {
                print("⚠️ 无法解析系统预设项目：\(doc.documentID)")
            }
        }
        
        // 4. 加载用户自定义
        print("\n----- 加载用户自定义项目 -----")
        let userSnapshot = try await db.collection("users")
            .document(userId)
            .collection("exercises")
            .getDocuments()
        
        print("📊 用户自定义文档数量：\(userSnapshot.documents.count)")
        print("\n用户自定义详细信息：")
        for doc in userSnapshot.documents {
            print("ID: \(doc.documentID)")
            print("名称: \(doc.data()["name"] ?? "未知")")
            print("类别: \(doc.data()["category"] ?? "未知")")
            print("系统预设标志: \(doc.data()["isSystemPreset"] ?? "未知")")
            print("---")
        }
        
        // 处理用户自定义，过滤掉系统预设
        for doc in userSnapshot.documents {
            // 跳过系统预设ID
            if systemIds.contains(doc.documentID) {
                continue
            }
            
            if let exercise = Exercise(dictionary: doc.data(), id: doc.documentID) {
                var userExercise = exercise
                userExercise.isSystemPreset = false  // 确保设置为用户自定义
                allExercises.append(userExercise)
            }
        }
        
        // 5. 数据统计和更新
        print("\n----- 数据统计 -----")
        let systemCount = allExercises.filter { $0.isSystemPreset }.count
        let userCount = allExercises.filter { !$0.isSystemPreset }.count
        print("系统预设总数：\(systemCount)")
        print("用户自定义总数：\(userCount)")
        print("总项目数：\(allExercises.count)")
        
        // 6. 更新数据
        isLoading = false
        exercises = allExercises
        saveToCache(allExercises)
        validateCurrentPage()  // 添加页码验证
        
        print("\n========== 数据加载完成 ==========")
    }
    
    // 修改为异步函数
    private func createSystemPresets() async throws {
                let db = Firestore.firestore()
                let batch = db.batch()
        let createdAt = Date()
        let updatedAt = createdAt
                
                let systemExercises = [
                    [
                        "category": "胸部",
                        "createdAt": createdAt,
                        "description": "在15-30度上斜卧推凳上，双手握住杠铃，重点锻炼上胸肌。",
                        "isSystemPreset": true,
                        "name": "上斜卧推",
                        "notes": "1. 控制斜度不要太大\n2. 肘部夹角约75度\n3. 感受上胸发力",
                        "unit": "kg",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "背部",
                        "createdAt": createdAt,
                        "description": "握距略宽于肩宽的杠铃划船，主要锻炼中背肌群。",
                        "isSystemPreset": true,
                        "name": "杠铃划船",
                        "notes": "1. 保持背部平直\n2. 收缩肩胛骨\n3. 控制下放速度",
                        "unit": "kg",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "腿部",
                        "createdAt": createdAt,
                        "description": "使用深蹲架进行深蹲，主要锻炼大腿和臀部肌肉。",
                        "isSystemPreset": true,
                        "name": "深蹲",
                        "notes": "1. 脚与肩同宽\n2. 保持膝盖不超过脚尖\n3. 下蹲至大腿与地面平行",
                        "unit": "kg",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "肩部",
                        "createdAt": createdAt,
                        "description": "站姿哑铃侧平举，主要锻炼肩部中束。",
                        "isSystemPreset": true,
                        "name": "哑铃侧平举",
                        "notes": "1. 保持手臂微弯\n2. 控制动作速度\n3. 不要借力摆动",
                        "unit": "kg",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "手臂",
                        "createdAt": createdAt,
                        "description": "站姿哑铃弯举，主要锻炼肱二头肌。",
                        "isSystemPreset": true,
                        "name": "哑铃弯举",
                        "notes": "1. 保持肘部固定\n2. 完全伸展手臂\n3. 收缩时完全收紧",
                        "unit": "kg",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "核心",
                        "createdAt": createdAt,
                        "description": "平板支撑，主要锻炼核心肌群。",
                        "isSystemPreset": true,
                        "name": "平板支撑",
                        "notes": "1. 保持身体一直线\n2. 收紧腹肌和臀肌\n3. 眼睛向下看",
                        "unit": "秒",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "胸部",
                        "createdAt": createdAt,
                        "description": "平卧哑铃飞鸟，主要锻炼胸大肌中部。",
                        "isSystemPreset": true,
                        "name": "哑铃飞鸟",
                        "notes": "1. 保持手臂微弯\n2. 控制动作范围\n3. 感受胸肌收缩",
                        "unit": "kg",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "有氧",
                        "createdAt": createdAt,
                        "description": "跑步机上进行中等强度跑步，有助于提升心肺功能。",
                        "isSystemPreset": true,
                        "name": "跑步",
                        "notes": "1. 保持均匀呼吸\n2. 适当调整坡度\n3. 穿着合适的跑鞋",
                        "unit": "分钟",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "全身",
                        "createdAt": createdAt,
                        "description": "高强度间歇训练（HIIT），结合多种动作提升全身耐力和力量。",
                        "isSystemPreset": true,
                        "name": "HIIT",
                        "notes": "1. 热身充分\n2. 控制动作质量\n3. 适当休息",
                        "unit": "分钟",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "背部",
                        "createdAt": createdAt,
                        "description": "引体向上，主要锻炼背阔肌和肱二头肌。",
                        "isSystemPreset": true,
                        "name": "引体向上",
                        "notes": "1. 全程控制动作\n2. 下放时缓慢\n3. 双手握距适中",
                        "unit": "次",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "腿部",
                        "createdAt": createdAt,
                        "description": "腿举机上进行腿举，主要锻炼大腿前侧和臀部。",
                        "isSystemPreset": true,
                        "name": "腿举",
                        "notes": "1. 脚掌放稳\n2. 推举时呼气\n3. 控制回收速度",
                        "unit": "kg",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "背部",
                        "createdAt": createdAt,
                        "description": "硬拉，主要锻炼下背部、臀部和大腿后侧。",
                        "isSystemPreset": true,
                        "name": "硬拉",
                        "notes": "1. 保持背部平直\n2. 使用腿部力量发力\n3. 控制杠铃路径",
                        "unit": "kg",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "胸部",
                        "createdAt": createdAt,
                        "description": "俯卧撑，主要锻炼胸部、肩部和三头肌。",
                        "isSystemPreset": true,
                        "name": "俯卧撑",
                        "notes": "1. 保持身体一直线\n2. 下压至胸部接近地面\n3. 呼吸均匀",
                        "unit": "次",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "手臂",
                        "createdAt": createdAt,
                        "description": "绳索下压，主要锻炼肱三头肌。",
                        "isSystemPreset": true,
                        "name": "绳索下压",
                        "notes": "1. 保持肘部固定\n2. 全程控制重量\n3. 收缩时完全伸展手臂",
                        "unit": "kg",
                        "updatedAt": updatedAt
                    ],
                    [
                        "category": "核心",
                        "createdAt": createdAt,
                        "description": "仰卧起坐，主要锻炼腹直肌。",
                        "isSystemPreset": true,
                        "name": "仰卧起坐",
                        "notes": "1. 保持下背部贴地\n2. 用腹肌发力起身\n3. 避免用力拉扯颈部",
                        "unit": "次",
                        "updatedAt": updatedAt
                    ]
                ] as [[String: Any]]
                
                print("📝 开始创建系统预设项目...")
                
                // 创建所有预设项目
                for exercise in systemExercises {
                    let docRef = db.collection("systemExercises").document()
                    batch.setData(exercise, forDocument: docRef)
                    print("📝 准备创建: \(exercise["name"] as? String ?? ""), 类别: \(exercise["category"] as? String ?? "")")
                }
                
                // 提交批量操作
                try await batch.commit()
                print("✅ 系统预设项目创建成功")
                
                // 创建成功后重新加载数据
                try await loadExercises()
    }
}

// 项目管理表单
struct ProjectManagementSheet: View {
    // MARK: - Properties
    @Environment(\.dismiss) private var dismiss
    @Binding var exercises: [Exercise]
    @Binding var showSystemExercises: Bool
    @Binding var showCustomExercises: Bool
    
    // 搜索和过滤
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var showingAddSheet = false
    @AppStorage("userId") private var userId: String = ""
    
    // UI 状态
    @State private var showAlert = false
    @State private var alertType: AlertType = .deleteConfirm(exercise: nil)
    @State private var isLoadingData = true
    @State private var showSuccessToast = false  // 添加这行
    @State private var deletedExerciseName = ""  // 添加这行
    
    // 展开状态
    @State private var isSystemExpanded = false
    @State private var isCustomExpanded = false
    
    // 分页相关
    @State private var systemPage = 1
    @State private var customPage = 1
    private let pageSize = 8
    
    // 限制相关
    @AppStorage("todayCreatedCount") private var todayCreatedCount: Int = 0
    @AppStorage("todayDeletedCount") private var todayDeletedCount: Int = 0
    @AppStorage("lastCreatedDate") private var lastCreatedDate: Double = Date().timeIntervalSince1970
    
    private let categories = ["全部", "胸部", "背部", "腿部", "肩部", "手臂", "核心", "有氧"]
    
    // 添加过滤后的数据计算属性
    private var filteredSystemExercises: [Exercise] {
        exercises.filter { exercise in
            exercise.isSystemPreset &&
            (searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText)) &&
            (selectedCategory == nil || selectedCategory == "全部" || exercise.category == selectedCategory)
        }
    }
    
    private var filteredCustomExercises: [Exercise] {
        exercises.filter { exercise in
            !exercise.isSystemPreset &&
            (searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText)) &&
            (selectedCategory == nil || selectedCategory == "全部" || exercise.category == selectedCategory)
        }
    }
    
    // 添加分页数据计算属性
    private var pagedSystemExercises: [Exercise] {
        let endIndex = min(systemPage * pageSize, filteredSystemExercises.count)
        return Array(filteredSystemExercises[0..<endIndex])
    }
    
    private var pagedCustomExercises: [Exercise] {
        let endIndex = min(customPage * pageSize, filteredCustomExercises.count)
        return Array(filteredCustomExercises[0..<endIndex])
    }
    
    // 添加是否有更多数据的计算属性
    private var hasMoreSystem: Bool {
        systemPage * pageSize < filteredSystemExercises.count
    }
    
    private var hasMoreCustom: Bool {
        customPage * pageSize < filteredCustomExercises.count
    }
    
    // 添加类别数量计算属性
    private func getExerciseCount(for category: String) -> Int {
        if category == "全部" {
            return exercises.count
        }
        return exercises.filter { $0.category == category }.count
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索栏
                SearchBar(text: $searchText)
                    .padding()
                
                // 类别选择器
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(categories, id: \.self) { category in
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(category)
                                        .font(.system(size: 14))
                                    
                                    // 添加数量标注
                                    Text("(\(getExerciseCount(for: category)))")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedCategory == category ? 
                                            getCategoryColor(category) : 
                                            Color(.systemGray6))
                                )
                                .foregroundColor(selectedCategory == category ? .white : .primary)
                                
                                // 下划线
                                Rectangle()
                                    .fill(getCategoryColor(category))
                                    .frame(height: 2)
                                    .opacity(selectedCategory == category ? 1 : 0)
                            }
                            .onTapGesture {
                                handleCategoryTap(category)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
                
                // 主列表内容
                ScrollView {
                    VStack(spacing: 0) {
                        // 系统预设组（固定标题）
                        if !filteredSystemExercises.isEmpty {
                            VStack(spacing: 0) {
                                // 固定的标题栏
                                Button(action: { withAnimation { isSystemExpanded.toggle() }}) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                            .font(.system(size: 18))
                                        
                                        Text("系统预设")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text("(\(filteredSystemExercises.count))")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: isSystemExpanded ? "chevron.down" : "chevron.right")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 14))
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                }
                                
                                // 可滚动的内容区域
                                if isSystemExpanded {
                                    VStack(spacing: 0) {
                                        ForEach(pagedSystemExercises) { exercise in
                                            // 为系统预设添加前缀
                                            let uniqueId = "system_\(exercise.id)"
                                            ExerciseRow(exercise: exercise) {}
                                                .id(uniqueId)  // 使用唯一 ID
                                                .padding(.horizontal)
                                                .padding(.vertical, 12)
                                                .background(Color(.systemBackground))
                                            
                                            Divider()
                                        }
                                        
                                        if hasMoreSystem {
                                            Button(action: { systemPage += 1 }) {
                                                HStack {
                                                    Text("加载更多")
                                                        .font(.subheadline)
                                                    Image(systemName: "arrow.down.circle.fill")
                                                }
                                                .frame(maxWidth: .infinity)
                                                .padding()
                                                .foregroundColor(.blue)
                                            }
                                            .background(Color(.systemBackground))
                                        }
                                    }
                                }
                                
                                Divider()  // 添加分组之间的分隔线
                            }
                        }
                        
                        // 自定义项目组（固定标题）
                        if !filteredCustomExercises.isEmpty {
                            VStack(spacing: 0) {
                                // 固定的标题栏
                                Button(action: { withAnimation { isCustomExpanded.toggle() }}) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(.blue)
                                            .font(.system(size: 18))
                                        
                                        Text("我的项目")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text("(\(filteredCustomExercises.count))")
                                            .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: isCustomExpanded ? "chevron.down" : "chevron.right")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 14))
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                }
                                
                                // 可滚动的内容区域
                                if isCustomExpanded {
                                    VStack(spacing: 0) {
                                        ForEach(pagedCustomExercises) { exercise in
                                            // 为用户自定义添加前缀
                                            let uniqueId = "custom_\(exercise.id)"
                                            ExerciseRow(exercise: exercise) {
                                                handleDelete(exercise)
                                            }
                                            .id(uniqueId)  // 使用唯一 ID
                                            .padding(.horizontal)
                                            .padding(.vertical, 12)
                                            .background(Color(.systemBackground))
                                            
                                            Divider()
                                        }
                                        
                                        if hasMoreCustom {
                                            Button(action: { customPage += 1 }) {
                                                HStack {
                                                    Text("加载更多")
                                                        .font(.subheadline)
                                                    Image(systemName: "arrow.down.circle.fill")
                                                }
                                                .frame(maxWidth: .infinity)
                                                .padding()
                                                .foregroundColor(.blue)
                                            }
                                            .background(Color(.systemBackground))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("项目管理")
            .navigationBarItems(
                leading: Button("关闭") { 
                    isSystemExpanded = false
                    isCustomExpanded = false
                    dismiss()
                },
                trailing: Button(action: { 
                    // 添加触觉反馈
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    
                    // 播放系统音效
                    AudioServicesPlaySystemSound(1104)
                    
                    showingAddSheet = true 
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加项目")
                    }
                }
            )
            // 修改这里，使用新的 AddExerciseView
            .sheet(isPresented: $showingAddSheet) {
                AddExerciseView { newExercise in
                    // 添加新项目到列表
                    exercises.append(newExercise)
                    
                    // 自动展开自定义项目组
                    withAnimation {
                        isCustomExpanded = true
                    }
                    
                    // 更新缓存
                    saveToCache(exercises)
                    
                    // 重置页码
                    customPage = 1
                }
            }
            // 监听搜索文本变化
            .onChange(of: searchText) { oldValue, newValue in
                if !newValue.isEmpty {
                    withAnimation {
                        isSystemExpanded = true
                        isCustomExpanded = true
                    }
                }
            }
            // 页面消失时处理
            .onDisappear {
                isSystemExpanded = false
                isCustomExpanded = false
            }
        }
        .overlay(alignment: .top) {
            if showSuccessToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(deletedExerciseName) 已删除")
                        .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 4)
            }
        }
        .alert(
            "确认删除",
            isPresented: $showAlert,
            presenting: alertType
        ) { type in
            switch type {
            case .deleteConfirm(let exercise):
                if let exercise = exercise {
                    Button("取消", role: .cancel) { }
                    Button("删除", role: .destructive) {
                        executeDelete(exercise)
                    }
                }
            case .deleteLimit:
                Button("知道了", role: .cancel) { }
            default:
                Button("确定", role: .cancel) { }
            }
        } message: { type in
            switch type {
            case .deleteConfirm(let exercise):
                if let exercise = exercise {
                    Text("确定要删除\"\(exercise.name)\"吗？此操作不可恢复。")
                } else {
                    Text("确定要删除吗？")
                }
            case .deleteLimit:
                Text("已达到今日删除上限（10次），请明天再试。")
            default:
                Text("")
            }
        }
    }
    
    // MARK: - Functions
    private func handleDelete(_ exercise: Exercise) {
        print("\n========== 准备删除项目 ==========")
        print("🗑️ 请求删除项目: \(exercise.name)")
        
        // 显示确认对话框
        alertType = .deleteConfirm(exercise: exercise)
        showAlert = true
    }
    
    private func handleAdd() {
        showingAddSheet = true
    }
    
    // 添加实际执行删除的函数
    private func executeDelete(_ exercise: Exercise) {
        print("🗑️ 确认删除项目: \(exercise.name)")
        
        // 检查是否是系统预设
        guard !exercise.isSystemPreset else {
            print("❌ 无法删除系统预设项目")
            return
        }
        
        // 检查删除限制
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = Date(timeIntervalSince1970: lastCreatedDate)
        
        if !Calendar.current.isDate(lastDate, inSameDayAs: today) {
            todayDeletedCount = 0
            lastCreatedDate = Date().timeIntervalSince1970
        }
        
        guard todayDeletedCount < 10 else {
            print("⚠️ 已达到每日删除上限")
            alertType = .deleteLimit
            showAlert = true
            return
        }
        
        // 执行删除操作
        let db = Firestore.firestore()
        db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
            .delete { [self] error in
                if let error = error {
                    print("❌ 删除失败: \(error.localizedDescription)")
                } else {
                    print("✅ 删除成功")
                    // 更新本地数据
                    if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
                        exercises.remove(at: index)
                    }
                    // 更新删除计数
                    todayDeletedCount += 1
                    
                    // 显示成功提示
                    deletedExerciseName = exercise.name
                    withAnimation {
                        showSuccessToast = true
                    }
                    // 3秒后隐藏提示
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            showSuccessToast = false
                        }
                    }
                }
            }
        
        print("========== 删除操作结束 ==========\n")
    }
    
    // 添加 loadExercises 函数
    private func loadExercises() async {
        print("\n========== 开始加载项目管理数据 ==========")
        isLoadingData = true
        
        // 1. 尝试从缓存加载
        if let cached = loadFromCache() {
            print("📦 从缓存加载数据成功")
            print("📊 缓存数据数量: \(cached.count)")
            if !cached.isEmpty {
                exercises = cached
                isLoadingData = false
                print("✅ 从缓存加载了 \(cached.count) 个项目")
                return
            } else {
                print("⚠️ 缓存为空，尝试从服务器加载")
            }
        }
        
        print("🌐 开始从 Firestore 加载数据...")
        
        do {
                        let db = Firestore.firestore()
            
            // 加载系统预设项目
            print("📥 加载系统预设项目...")
            let systemSnapshot = try await db.collection("systemExercises")
                .getDocuments()
            
            var systemExercises: [Exercise] = []
            for doc in systemSnapshot.documents {
                if let exercise = Exercise(dictionary: doc.data(), id: doc.documentID) {
                    systemExercises.append(exercise)
                }
            }
            print("✅ 加载了 \(systemExercises.count) 个系统预设项目")
            
            // 加载用户自定义项目
            print("📥 加载用户自定义项目...")
            let userSnapshot = try await db.collection("users")
                            .document(userId)
                            .collection("exercises")
                .getDocuments()
            
            var userExercises: [Exercise] = []
            for doc in userSnapshot.documents {
                if let exercise = Exercise(dictionary: doc.data(), id: doc.documentID) {
                    userExercises.append(exercise)
                }
            }
            print("✅ 加载了 \(userExercises.count) 个用户自定义项目")
            
            // 合并数据
            let allExercises = systemExercises + userExercises
            print("📊 总计加载 \(allExercises.count) 个项目")
            
            // 更新 UI 和缓存
            exercises = allExercises
            saveToCache(allExercises)
            
        } catch {
            print("❌ 加载失败: \(error.localizedDescription)")
        }
        
        isLoadingData = false
        print("========== 数据加载结束 ==========\n")
    }
    
    // 添加缓存相关函数
    private func loadFromCache() -> [Exercise]? {
        if let data = UserDefaults.standard.data(forKey: "cachedExercises"),
           let cached = try? JSONDecoder().decode([Exercise].self, from: data) {
            print("📦 从缓存读取成功")
            return cached
        }
        print("⚠️ 缓存不存在或已过期")
        return nil
    }
    
    private func saveToCache(_ exercises: [Exercise]) {
        if let encoded = try? JSONEncoder().encode(exercises) {
            UserDefaults.standard.set(encoded, forKey: "cachedExercises")
            print("💾 保存到缓存：\(exercises.count) 个项目")
        }
    }
    
    // 修改 handleCategoryTap 函数
    private func handleCategoryTap(_ category: String) {
        // 添加触觉反馈
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // 播放系统音效
        AudioServicesPlaySystemSound(1104)
        
        // 更新选中的类别
        withAnimation(.easeInOut) {
            selectedCategory = category
            // 选择类别时自动展开
            if category != "全部" {
                isSystemExpanded = true
                isCustomExpanded = true
            }
        }
    }
}

// MARK: - Subviews
private struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
                TextField("搜索训练项目...", text: $text)
                    .font(.system(size: 16))
                
                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

private struct CategorySelector: View {
    let categories: [String]
    @Binding var selectedCategory: String?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(categories, id: \.self) { category in
                    CategoryButton(
                        title: category,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
        }
    }
}

private struct ExerciseList: View {
    let systemExercises: [Exercise]
    let customExercises: [Exercise]
    let hasMoreSystem: Bool
    let hasMoreCustom: Bool
    let onLoadMoreSystem: () -> Void
    let onLoadMoreCustom: () -> Void
    let onDelete: (Exercise) -> Void
    
    var body: some View {
        List {
            if systemExercises.isEmpty && customExercises.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("暂无训练项目")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("点击右上角添加按钮开始创建")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                // 系统预设项目组
                ExerciseGroup(
                    title: "系统预设",
                    icon: "star.fill",
                    exercises: systemExercises,
                    hasMore: hasMoreSystem,
                    onLoadMore: onLoadMoreSystem,
                    onDelete: onDelete,
                    isDeletable: false
                )
                
                // 自定义项目组
                ExerciseGroup(
                    title: "我的项目",
                    icon: "folder.fill",
                    exercises: customExercises,
                    hasMore: hasMoreCustom,
                    onLoadMore: onLoadMoreCustom,
                    onDelete: onDelete,
                    isDeletable: true
                )
            }
        }
        .listStyle(.plain)
    }
}

// 类别按钮组件
struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 14))
                        .fontWeight(isSelected ? .semibold : .regular)
                }
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? 
                            getCategoryColor(title) : 
                            Color(.systemGray6))
                        .shadow(color: isSelected ? 
                            getCategoryColor(title).opacity(0.3) : 
                            Color.clear,
                            radius: 4, x: 0, y: 2)
                )
                
                // 添加下划线
                Rectangle()
                    .fill(getCategoryColor(title))
                    .frame(height: 2)
                    .opacity(isSelected ? 1 : 0)
            }
        }
    }
}

private struct CloseButton: View {
    let action: () -> Void
    
    var body: some View {
        Button("关闭") {
            action()
        }
    }
}

private struct AddButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
        }
    }
}

private struct ExerciseGroup: View {
    let title: String
    let icon: String
    let exercises: [Exercise]
    let hasMore: Bool
    let onLoadMore: () -> Void
    let onDelete: (Exercise) -> Void
    let isDeletable: Bool
    
    var body: some View {
        Section(header: 
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.headline)
            .foregroundColor(.primary)
            .padding(.vertical, 8)
        ) {
            ForEach(exercises) { exercise in
                ExerciseRow(exercise: exercise, onDelete: {
                    if isDeletable {
                        onDelete(exercise)
                    }
                })
            }
            
            if hasMore {
                Button(action: onLoadMore) {
                    Text("加载更多...")
                                    .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

private struct ExerciseRow: View {
    let exercise: Exercise
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .medium))
                    
                    Text(exercise.category)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !exercise.isSystemPreset {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            
            // 描述和注意事项
            if !exercise.description.isEmpty || !exercise.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !exercise.description.isEmpty {
                        Text(exercise.description)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    if !exercise.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("注意事项:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(exercise.notes)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.top, 4)
            }
            
            // 单位信息
            if let unit = exercise.unit {
                Text("单位: \(unit)")
                    .font(.system(size: 12))
                .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
    }
}

// 添加 PR 记录卡片视图
struct PRRecordCard: View {
    let exercise: Exercise
    let maxRecord: Double?
    let lastRecordDate: Date?
    @State private var showingAddRecord = false // 添加这一行
    
    var body: some View {
        Button(action: { 
            // 添加触觉反馈
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            
            // 播放系统音效
            AudioServicesPlaySystemSound(1520)
            
            showingAddRecord = true // 修改这里,显示添加记录页面
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // 标题和类别
                HStack {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(exercise.category)
                        .font(.system(size: 13))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(getCategoryColor(exercise.category).opacity(0.1))
                        .foregroundColor(getCategoryColor(exercise.category))
                        .cornerRadius(12)
                }
                
                // 极限记录
                VStack(alignment: .leading, spacing: 6) {
                    Text("历史最佳")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    if let maxRecord = maxRecord {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(maxRecord, specifier: "%.1f")")
                                .font(.system(size: 22, weight: .bold))
                            Text(exercise.unit ?? "")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("未测试")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
                
                // 最近记录和创造时间
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        if let date = lastRecordDate {
                            Text("创造于: \(date.formatted(.dateTime.month().day().hour().minute()))")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        } else {
                            Text("暂无记录")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                        if let maxRecord = maxRecord {
                            Text("上次极限: \(maxRecord, specifier: "%.1f") \(exercise.unit ?? "")")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        } else {
                            Text("等待挑战")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PRCardButtonStyle()) // 添加自定义按钮样式
        .sheet(isPresented: $showingAddRecord) {
            AddPRRecordView(exercise: exercise)
        }
    }
}

// 添加详情视图
struct ExerciseDetailView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部信息
                VStack(spacing: 12) {
                    Text(exercise.name)
                        .font(.title2.bold())
                    
                    HStack(spacing: 8) {
                        Text(exercise.category)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                        
                        if let unit = exercise.unit {
                            Text(unit)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                
                // 选项卡
                Picker("", selection: $selectedTab) {
                    Text("极限记录").tag(0)
                    Text("历史记录").tag(1)
                    Text("进步图表").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                TabView(selection: $selectedTab) {
                    // 极限记录视图
                    PRHistoryView(exercise: exercise)
                        .tag(0)
                    
                    // 历史记录视图
                    RecordHistoryView(exercise: exercise)
                        .tag(1)
                    
                    // 进步图表视图
                    ProgressChartView(exercise: exercise)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationBarItems(
                leading: Button("关闭") { dismiss() },
                trailing: Menu {
                    Button(role: .destructive, action: { showingDeleteAlert = true }) {
                        Label("删除记录", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.blue)
                }
            )
            .alert("删除确认", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    // 执行删除操作
                }
            } message: {
                Text("确定要删除这条记录吗？此操作不可恢复。")
            }
        }
    }
}

// 添加类别按钮带计数
struct CategoryButtonWithCount: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    private func getCategoryColor(_ category: String) -> Color {
        switch category {
        case "胸部":
            return .red
        case "背部":
            return .blue
        case "腿部":
            return .purple
        case "肩部":
            return .orange
        case "手臂":
            return .green
        case "核心":
            return .pink
        case "有氧":
            return .cyan
        default:
            return .blue
        }
    }
    
    var body: some View {
        Button(action: {
            // 添加触觉反馈
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
            
            // 播放系统音效
            AudioServicesPlaySystemSound(1104) // 使用按钮音效
            
            action()
        }) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .font(.system(size: 12))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? 
                                Color.white.opacity(0.2) : 
                                getCategoryColor(title).opacity(0.1))
                    )
            }
            .font(.system(size: 14))
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? 
                        getCategoryColor(title) : 
                        Color(.systemGray6))
                    .shadow(color: isSelected ? 
                        getCategoryColor(title).opacity(0.3) : 
                        Color.clear,
                        radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(CategoryButtonStyle(isSelected: isSelected))
    }
}

// 添加 PR 历史记录视图
struct PRHistoryView: View {
    let exercise: Exercise
    
    var body: some View {
        VStack {
            Text("暂无极限记录")
                .foregroundColor(.secondary)
                .padding()
        }
    }
}

// 添加历史记录视图
struct RecordHistoryView: View {
    let exercise: Exercise
    
    var body: some View {
        VStack {
            Text("暂无历史记录")
                .foregroundColor(.secondary)
                .padding()
        }
    }
}

// 添加进步图表视图
struct ProgressChartView: View {
    let exercise: Exercise
    
    var body: some View {
        VStack {
            Text("暂无进步数据")
                .foregroundColor(.secondary)
                .padding()
        }
    }
}

// 添加骨架屏组件
struct PRRecordCardSkeleton: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题和类别骨架
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 16)
                Spacer()
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 24)
            }
            
            // 极限记录骨架
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 13)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 22)
            }
            
            // 时间信息骨架
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 150, height: 13)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 13)
            }
        }
        .padding(16)
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        .opacity(isAnimating ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

// 添加 ScrollOffsetPreferenceKey
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// 修改 RefreshControl
struct RefreshControl: View {
    @Binding var isRefreshing: Bool
    let action: () -> Void
    let lastSyncTimeString: String
    @State private var hasTriggeredRefresh = false
    
    var body: some View {
        GeometryReader { geometry in
            let offset = geometry.frame(in: .named("scroll")).minY
            let progress = min(max(0, offset / 80), 1)
            
            VStack(spacing: 8) {
                if isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.blue)
                        Text("正在刷新...")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                } else {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        // 修复箭头旋转角度计算
                        .rotationEffect(.degrees(Double(progress) * -180))
                }
                
                Text(lastSyncTimeString == "未同步" ? 
                    "下拉刷新" : 
                    "上次同步：\(lastSyncTimeString)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(width: geometry.size.width)
            .frame(height: 40)
            .offset(y: max(-20, -40 + offset * 0.8))
            .opacity(progress)
        }
        .frame(height: 0)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            if !isRefreshing && !hasTriggeredRefresh && offset > 100 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    hasTriggeredRefresh = true
                }
                
                // 添加触发动画
                withAnimation(.easeInOut(duration: 0.3)) {
                    action()
                }
            }
            
            if offset < 10 {
                hasTriggeredRefresh = false
            }
        }
    }
}

// MARK: - Add Exercise Sheet
struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var exercises: [Exercise]
    
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
    @State private var showSuccessAnimation = false
    
    // 常量
    private let categories = ["胸部", "背部", "腿部", "肩部", "手臂", "核心", "有氧"]
    private let units = ["kg", "次", "分钟", "米"]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 名称输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("项目名称")
                            .font(.headline)
                        TextField("例如：卧推", text: $name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    // 类别选择
                    VStack(alignment: .leading, spacing: 8) {
                        Text("类别")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(categories, id: \.self) { category in
                                    CategoryButton(
                                        title: category,
                                        isSelected: selectedCategory == category,
                                        action: { selectedCategory = category }
                                    )
                                }
                            }
                        }
                    }
                    
                    // 单位选择
                    VStack(alignment: .leading, spacing: 8) {
                        Text("计量单位")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(units, id: \.self) { unit in
                                    CategoryButton(
                                        title: unit,
                                        isSelected: selectedUnit == unit,
                                        action: { selectedUnit = unit }
                                    )
                                }
                            }
                        }
                    }
                    
                    // 描述输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("描述")
                            .font(.headline)
                        TextEditor(text: $description)
                            .frame(height: 100)
                            .padding(4)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    
                    // 注意事项输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("注意事项")
                            .font(.headline)
                        TextEditor(text: $notes)
                            .frame(height: 100)
                            .padding(4)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    
                    // 保存按钮
                    Button(action: saveExercise) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("保存中...")
                            } else {
                                Text("保存")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isFormValid ? Color.blue : Color.gray)
                        )
                        .foregroundColor(.white)
                    }
                    .disabled(!isFormValid || isLoading)
                }
                .padding()
            }
            .navigationTitle("添加项目")
            .navigationBarItems(
                leading: Button("取消") { dismiss() }
            )
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var isFormValid: Bool {
        !name.isEmpty && selectedCategory != nil && selectedUnit != nil
    }
    
    // MARK: - Functions
    private func saveExercise() {
        guard isFormValid else { return }
        
        isLoading = true
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
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            showError = true
            errorMessage = "用户ID不存在"
            isLoading = false
            return
        }
        
        db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
            .setData(exercise.dictionary) { error in
                if let error = error {
                    showError = true
                    errorMessage = "保存失败: \(error.localizedDescription)"
                    isLoading = false
                } else {
                    exercises.append(exercise)
                    showSuccessAnimation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isLoading = false
                        dismiss()
                    }
                }
            }
    }
}

// 在文件顶部添加 Exercise 扩展
extension Exercise {
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "category": category,
            "description": description,
            "notes": notes,
            "isSystemPreset": isSystemPreset,
            "createdAt": createdAt,
            "updatedAt": updatedAt
        ]
        
        // 只处理可选值
        if let unit = unit {
            dict["unit"] = unit
        }
        
        if let maxRecord = maxRecord {
            dict["maxRecord"] = maxRecord
        }
        
        if let lastRecordDate = lastRecordDate {
            dict["lastRecordDate"] = lastRecordDate
        }
        
        return dict
    }
}

// 添加 Exercise 初始化方法
extension Exercise {
    init?(dictionary: [String: Any], id: String) {
        print("🔍 解析文档 ID: \(id)")
        
        guard let name = dictionary["name"] as? String else {
            print("❌ 缺少名称字段")
            return nil
        }
        guard let category = dictionary["category"] as? String else {
            print("❌ 缺少类别字段")
            return nil
        }
        guard let isSystemPreset = dictionary["isSystemPreset"] as? Bool else {
            print("❌ 缺少系统预设标志")
            return nil
        }
        
        // 处理时间戳
        let createdAt: Date
        let updatedAt: Date
        
        if let timestamp = dictionary["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            print("❌ 缺少创建时间或格式错误")
            return nil
        }
        
        if let timestamp = dictionary["updatedAt"] as? Timestamp {
            updatedAt = timestamp.dateValue()
        } else {
            print("❌ 缺少更新时间或格式错误")
            return nil
        }
        
        self.id = id
        self.name = name
        self.category = category
        self.description = dictionary["description"] as? String ?? ""
        self.notes = dictionary["notes"] as? String ?? ""
        self.isSystemPreset = isSystemPreset
        self.unit = dictionary["unit"] as? String
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.maxRecord = dictionary["maxRecord"] as? Double
        self.lastRecordDate = (dictionary["lastRecordDate"] as? Timestamp)?.dateValue()
        
        print("✅ 成功创建运动项目: \(name)")
    }
}

// 2. 添加自定义按钮样式
private struct PRCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// 4. 添加类别按钮样式
private struct CategoryButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    MaxRecordsView()
} 