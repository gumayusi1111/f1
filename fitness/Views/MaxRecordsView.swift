import SwiftUI
import FirebaseFirestore

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
        Int(ceil(Double(filteredPRs.count) / Double(pageSize)))
    }
    
    // 获取当前页的项目
    private var currentPageItems: [Exercise] {
        let startIndex = (currentPage - 1) * pageSize
        let endIndex = min(startIndex + pageSize, filteredPRs.count)
        return Array(filteredPRs[startIndex..<endIndex])
    }
    
    // 1. 添加缓存键常量
    private let PR_CACHE_KEY = "cachedPRRecords"
    
    // 在 MaxRecordsView 中添加状态来追踪 sheet 的显示
    @State private var isSheetPresented = false
    
    init() {
        setupFirestore()
    }
    
    private func setupFirestore() {
        let db = Firestore.firestore()
        let settings = FirestoreSettings()
        // 使用新的 API 设置缓存，不需要传参数
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
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
    
    // 2. 修改 performRefresh 函数
    private func performRefresh() async {
        guard !isRefreshing else { return }
        
        if !canRefresh() {
            showRefreshLimitAlert = true
            return
        }
        
        print("\n========== 开始刷新数据 ==========")
        print("📱 开始刷新: \(Date())")
        
        isRefreshing = true
        
        do {
            // 并行加载数据
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await loadExercises()
                }
                
                group.addTask {
                    try await loadRecentPRs()
                }
                
                try await group.waitForAll()
            }
            
            // 更新刷新时间
            updateLastRefreshTime()
            lastSyncDate = Date() // 更新最后同步日期
            updateLastSyncTime()
            
            print("✅ 数据刷新成功")
            print("📅 最后同步时间: \(lastSyncTimeString)")
            
        } catch {
            print("❌ 刷新失败: \(error.localizedDescription)")
        }
        
        isRefreshing = false
        print("========== 刷新结束 ==========\n")
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
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
            }
            .refreshable {
                await performRefresh()
            }
            .alert("刷新限制", isPresented: $showRefreshLimitAlert) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text("请等待一分钟后再次刷新")
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
    
    // 过滤后的PR记录
    private var filteredPRs: [Exercise] {
        recentPRs.filter { exercise in
            let matchesSearch = prSearchText.isEmpty || 
                exercise.name.localizedCaseInsensitiveContains(prSearchText)
            
            let matchesCategory = selectedPRCategory == nil || 
                selectedPRCategory == "全部" || 
                exercise.category == selectedPRCategory
            
            return matchesSearch && matchesCategory
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
        print("\n📱 开始加载运动项目...")
        isLoading = true
        
        // 先尝试从缓存加载
        if let cached = loadFromCache() {
            print("📦 从缓存加载数据...")
            self.exercises = cached
            isLoading = false
            print("✅ 从缓存加载了 \(cached.count) 个项目")
            
            if !isRefreshing {
                return
            }
        }
        
        guard connectivityManager.isOnline else {
            print("⚠️ 离线状态，使用缓存数据")
            isLoading = false
            return
        }
        
        print("🌐 正在从服务器获取最新数据...")
        
            let db = Firestore.firestore()
        let snapshot = try await db.collection("users")
                .document(userId)
                .collection("exercises")
            .getDocuments()
        
                    isLoading = false
                    
        let loadedExercises = snapshot.documents.compactMap { doc -> Exercise? in
            Exercise(dictionary: doc.data(), id: doc.documentID)
        }
        
        print("✅ 成功加载 \(loadedExercises.count) 个项目")
        exercises = loadedExercises
        saveToCache(loadedExercises)
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
                                            ExerciseRow(exercise: exercise) {}
                                                .padding(.horizontal)
                                                .padding(.vertical, 12)
                                                .background(Color(.systemBackground))
                                            
                                            Divider()  // 添加分隔线
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
                                    ExerciseRow(exercise: exercise) {
                                                handleDelete(exercise)
                                            }
                                            .padding(.horizontal)
                                            .padding(.vertical, 12)
                                            .background(Color(.systemBackground))
                                            
                                            Divider()  // 添加分隔线
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
                    // 关闭时收起展开的部分
                    isSystemExpanded = false
                    isCustomExpanded = false
                    dismiss()
                },
                trailing: Button(action: handleAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加项目")
                    }
                }
            )
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
    }
    
    // MARK: - Functions
    private func handleDelete(_ exercise: Exercise) {
        // 实现删除逻辑
    }
    
    private func handleAdd() {
        showingAddSheet = true
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
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
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
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            ExerciseDetailView(exercise: exercise)
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
        Button(action: action) {
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

#Preview {
    MaxRecordsView()
} 