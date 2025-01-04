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
                updateLastSyncTime() // 初始化同步时间显示
                Task {
                    await performRefresh()
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
        
        return try await withCheckedThrowingContinuation { continuation in
            let db = Firestore.firestore()
            db.collection("users")
                .document(userId)
                .collection("exercises")
                .getDocuments { snapshot, error in
                    isLoading = false
                    
                    if let error = error {
                        print("❌ 加载失败: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    if let documents = snapshot?.documents {
                        let loadedExercises = documents.compactMap { doc in
                            try? doc.data(as: Exercise.self)
                        }
                        self.exercises = loadedExercises
                        
                        // 保存到缓存
                        self.saveToCache(loadedExercises)
                        print("✅ 成功从服务器加载 \(loadedExercises.count) 个项目")
                        print("💾 数据已保存到缓存")
                        continuation.resume(returning: ())
                    } else {
                        print("⚠️ 没有找到运动项目数据")
                        continuation.resume(returning: ())
                    }
                }
        }
    }
    
    // 修改为异步函数
    private func createSystemExercises() {
        Task {
            do {
                let db = Firestore.firestore()
                let batch = db.batch()
                
                // 创建特定的时间戳
                let createdAt = Timestamp(date: Date(timeIntervalSince1970: 1704293287))
                let updatedAt = Timestamp(date: Date(timeIntervalSince1970: 1704293297))
                
                // 预设项目数据
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
                
            } catch {
                print("❌ 创建系统预设项目失败: \(error.localizedDescription)")
            }
        }
    }
}

// 项目管理表单
struct ProjectManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var exercises: [Exercise]
    @Binding var showSystemExercises: Bool
    @Binding var showCustomExercises: Bool
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var showingAddSheet = false
    @AppStorage("userId") private var userId: String = ""
    
    // 添加分页相关状态
    @State private var currentPage = 1
    private let pageSize = 10
    @State private var hasMoreItems = true
    @State private var isLoadingMore = false
    
    // 为系统预设和自定义项目分别添加页码
    @State private var systemExercisesPage = 1
    @State private var customExercisesPage = 1
    
    // 添加每日创建限制相关的属性
    @AppStorage("todayCreatedCount") private var todayCreatedCount: Int = 0
    @AppStorage("lastCreatedDate") private var lastCreatedDate: Double = Date().timeIntervalSince1970
    @State private var showAlert = false
    @State private var alertType: AlertType = .deleteConfirm(exercise: nil)
    
    // 添加删除限制相关的属性
    @AppStorage("todayDeletedCount") private var todayDeletedCount: Int = 0
    
    // 定义警告类型
    private enum AlertType {
        case deleteConfirm(exercise: Exercise?)
        case limitReached
        case deleteLimit
    }
    
    private let categories = ["全部", "胸部", "背部", "腿部", "肩部", "手臂", "核心", "有氧"]
    
    // 过滤后的运动项目
    private var filteredExercises: [Exercise] {
        exercises.filter { exercise in
            let matchesSearch = searchText.isEmpty || 
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.description.localizedCaseInsensitiveContains(searchText)
            
            let matchesCategory = selectedCategory == nil || 
                selectedCategory == "全部" || 
                exercise.category == selectedCategory
            
            let matchesType = (exercise.isSystemPreset && showSystemExercises) ||
                (!exercise.isSystemPreset && showCustomExercises)
            
            return matchesSearch && matchesCategory && matchesType
        }
    }
    
    // 分页过滤的运动项目
    private var pagedSystemExercises: [Exercise] {
        let filtered = filteredExercises.filter(\.isSystemPreset)
        if filtered.count > pageSize {
            let endIndex = min(systemExercisesPage * pageSize, filtered.count)
            return Array(filtered[0..<endIndex])
        }
        return filtered
    }
    
    private var pagedCustomExercises: [Exercise] {
        let filtered = filteredExercises.filter { !$0.isSystemPreset }
        if filtered.count > pageSize {
            let endIndex = min(customExercisesPage * pageSize, filtered.count)
            return Array(filtered[0..<endIndex])
        }
        return filtered
    }
    
    private var hasMoreSystemExercises: Bool {
        let filtered = filteredExercises.filter(\.isSystemPreset)
        return filtered.count > systemExercisesPage * pageSize
    }
    
    private var hasMoreCustomExercises: Bool {
        let filtered = filteredExercises.filter { !$0.isSystemPreset }
        return filtered.count > customExercisesPage * pageSize
    }
    
    // 修改加载更多函数
    private func loadMoreSystem() {
        systemExercisesPage += 1
    }
    
    private func loadMoreCustom() {
        customExercisesPage += 1
    }
    
    // 监听展开状态变化
    private func onSystemExercisesExpandChanged(_ isExpanded: Bool) {
        if !isExpanded {
            systemExercisesPage = 1  // 收起时重置页码
        }
    }
    
    private func onCustomExercisesExpandChanged(_ isExpanded: Bool) {
        if !isExpanded {
            customExercisesPage = 1  // 收起时重置页码
        }
    }
    
    // 检查是否可以创建新项目
    private func canCreateNewExercise() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = Date(timeIntervalSince1970: lastCreatedDate)
        let lastCreatedDay = Calendar.current.startOfDay(for: lastDate)
        
        // 如果是新的一天，重置计数
        if today != lastCreatedDay {
            todayCreatedCount = 0
            lastCreatedDate = Date().timeIntervalSince1970
            return true
        }
        
        return todayCreatedCount < 10
    }
    
    // 检查是否可以删除项目
    private func canDeleteExercise() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = Date(timeIntervalSince1970: lastCreatedDate)
        let lastCreatedDay = Calendar.current.startOfDay(for: lastDate)
        
        // 如果是新的一天，重置计数
        if today != lastCreatedDay {
            todayDeletedCount = 0
            return true
        }
        
        return todayDeletedCount < 10
    }
    
    // 修改删除函数
    private func deleteExercise(_ exercise: Exercise) {
        if canDeleteExercise() {
            alertType = .deleteConfirm(exercise: exercise)
            showAlert = true
        } else {
            alertType = .deleteLimit
            showAlert = true
        }
    }
    
    // 修改搜索文本变化监听函数
    private func onSearchTextChanged() {
        // 如果搜索框为空，不自动展开
        if searchText.isEmpty {
            withAnimation {
                // 如果有选择的类别，保持展开状态
                if let category = selectedCategory, category != "全部" {
                    let hasSystemMatches = exercises.contains { exercise in
                        exercise.isSystemPreset && exercise.category == category
                    }
                    let hasCustomMatches = exercises.contains { exercise in
                        !exercise.isSystemPreset && exercise.category == category
                    }
                    showSystemExercises = hasSystemMatches
                    showCustomExercises = hasCustomMatches
                } else {
                    // 如果没有选择类别且搜索框为空，折叠所有
                    showSystemExercises = false
                    showCustomExercises = false
                }
            }
            return
        }
        
        // 搜索框不为空时，检查匹配项并展开相应区域
        let hasSystemMatches = exercises.contains { exercise in
            exercise.isSystemPreset && (
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.description.localizedCaseInsensitiveContains(searchText)
            ) && (selectedCategory == nil || selectedCategory == "全部" || 
                  exercise.category == selectedCategory)
        }
        
        let hasCustomMatches = exercises.contains { exercise in
            !exercise.isSystemPreset && (
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.description.localizedCaseInsensitiveContains(searchText)
            ) && (selectedCategory == nil || selectedCategory == "全部" || 
                  exercise.category == selectedCategory)
        }
        
        withAnimation {
            showSystemExercises = hasSystemMatches
            showCustomExercises = hasCustomMatches
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                    .padding()
                    .onChange(of: searchText) { oldValue, newValue in
                        if newValue != oldValue {
                            onSearchTextChanged()
                        }
                    }
                
                // 类别选择
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(categories, id: \.self) { category in
                            // 计算每个类别的项目数量
                            let count = category == "全部" ? 
                                exercises.count :
                                exercises.filter { $0.category == category }.count
                            
                            CategoryButtonWithCount(
                                title: category,
                                count: count,
                                isSelected: selectedCategory == category,
                                action: { 
                                    selectedCategory = category
                                    // 当选择类别时自动展开相关区域
                                    if category != "全部" {
                                        let hasSystemMatches = exercises.contains { exercise in
                                            exercise.isSystemPreset && exercise.category == category
                                        }
                                        let hasCustomMatches = exercises.contains { exercise in
                                            !exercise.isSystemPreset && exercise.category == category
                                        }
                                        withAnimation {
                                            showSystemExercises = hasSystemMatches
                                            showCustomExercises = hasCustomMatches
                                        }
                                    } else {
                                        withAnimation {
                                            showSystemExercises = true
                                            showCustomExercises = true
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
                
                List {
                    // 系统预设项目
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { showSystemExercises },
                            set: { newValue in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showSystemExercises = newValue
                                    onSystemExercisesExpandChanged(newValue)
                                }
                            }
                        ),
                        content: {
                            VStack(spacing: 12) {
                                ForEach(pagedSystemExercises) { exercise in
                                    ExerciseRow(exercise: exercise)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                                
                                if hasMoreSystemExercises {
                                    Button(action: loadMoreSystem) {
                                        HStack {
                                            Spacer()
                                            Text("加载更多")
                                                .foregroundColor(.blue)
                                                .font(.system(size: 15))
                                            Spacer()
                                        }
                                        .padding(.vertical, 12)
                                        .background(Color(.systemGray6).opacity(0.5))
                                        .cornerRadius(8)
                                    }
                                    .padding(.top, 8)
                                } else if !pagedSystemExercises.isEmpty {
                                    // 当所有项目都加载完成时显示提示
                                    HStack {
                                        Spacer()
                                        Text("已加载全部")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 14))
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        },
                        label: {
                            HStack(spacing: 12) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .rotationEffect(.degrees(showSystemExercises ? 90 : 0))
                                Text("系统预设项目")
                                    .font(.headline)
                                Spacer()
                                let count = exercises.filter { exercise in
                                    exercise.isSystemPreset && 
                                    (selectedCategory == nil || selectedCategory == "全部" || exercise.category == selectedCategory) &&
                                    (searchText.isEmpty || 
                                     exercise.name.localizedCaseInsensitiveContains(searchText) ||
                                     exercise.description.localizedCaseInsensitiveContains(searchText))
                                }.count
                                Text("\(count)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showSystemExercises)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .padding(.horizontal, 16)
                    
                    // 自定义项目
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { showCustomExercises },
                            set: { newValue in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showCustomExercises = newValue
                                    onCustomExercisesExpandChanged(newValue)
                                }
                            }
                        ),
                        content: {
                            VStack(spacing: 12) {
                                ForEach(pagedCustomExercises) { exercise in
                                    ExerciseRow(exercise: exercise) {
                                        deleteExercise(exercise)
                                    }
                                    .padding(.vertical, 6)
                                }
                                
                                if hasMoreCustomExercises {
                                    Button(action: loadMoreCustom) {
                                        HStack {
                                            Spacer()
                                            Text("加载更多")
                                                .foregroundColor(.blue)
                                                .font(.system(size: 15))
                                            Spacer()
                                        }
                                        .padding(.vertical, 12)
                                        .background(Color(.systemGray6).opacity(0.5))
                                        .cornerRadius(8)
                                    }
                                    .padding(.top, 8)
                                } else if !pagedCustomExercises.isEmpty {
                                    // 当所有项目都加载完成时显示提示
                                    HStack {
                                        Spacer()
                                        Text("已加载全部")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 14))
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        },
                        label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                Text("我的项目")
                                    .font(.headline)
                                Spacer()
                                let count = exercises.filter { exercise in
                                    !exercise.isSystemPreset && 
                                    (selectedCategory == nil || selectedCategory == "全部" || exercise.category == selectedCategory) &&
                                    (searchText.isEmpty || 
                                     exercise.name.localizedCaseInsensitiveContains(searchText) ||
                                     exercise.description.localizedCaseInsensitiveContains(searchText))
                                }.count
                                Text("\(count)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .padding(.horizontal, 16)
                }
                .listStyle(PlainListStyle())
                .environment(\.defaultMinListRowHeight, 0)
            }
            .navigationTitle("项目管理")
            .navigationBarItems(
                leading: Button(action: { dismiss() }) {
                    Text("关闭")
                        .foregroundColor(.blue)
                },
                trailing: Button(action: {
                    if canCreateNewExercise() {
                        showingAddSheet = true
                    } else {
                        alertType = .limitReached
                        showAlert = true
                    }
                }) {
                    Text("添加项目")
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            )
            .sheet(isPresented: $showingAddSheet) {
                AddExerciseSheet(exercises: $exercises)
            }
        }
        .alert(isPresented: $showAlert) {
            switch alertType {
            case .deleteConfirm(let exercise):
                guard let exercise = exercise else { return Alert(title: Text("错误")) }
                return Alert(
                    title: Text("删除确认"),
                    message: Text("确定要删除「\(exercise.name)」吗？此操作不可恢复。"),
                    primaryButton: .destructive(Text("删除")) {
                        // 执行删除
                        let db = Firestore.firestore()
                        db.collection("users")
                            .document(userId)
                            .collection("exercises")
                            .document(exercise.id)
                            .delete { error in
                                if let error = error {
                                    print("❌ 删除失败: \(error)")
                                    return
                                }
                                
                                DispatchQueue.main.async {
                                    withAnimation {
                                        exercises.removeAll { $0.id == exercise.id }
                                        // 更新删除计数
                                        todayDeletedCount += 1
                                    }
                                }
                            }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .limitReached:
                return Alert(
                    title: Text("创建限制"),
                    message: Text("您今天已创建 \(todayCreatedCount) 个项目，达到每日上限（10个）。请明天再试！"),
                    dismissButton: .default(Text("知道了"))
                )
            case .deleteLimit:
                return Alert(
                    title: Text("删除限制"),
                    message: Text("您今天已删除 \(todayDeletedCount) 个项目，达到每日上限（10个）。请明天再试！"),
                    dismissButton: .default(Text("知道了"))
                )
            }
        }
        .onDisappear {
            // 关闭页面时重置所有状态
            showSystemExercises = false
            showCustomExercises = false
            searchText = ""  // 清空搜索文本
            selectedCategory = nil  // 重置类别选择
        }
    }
}

// 搜索栏组件
struct SearchBar: View {
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

// 类别按钮组件
struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.blue)
                                .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        } else {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                .background(Color.white.cornerRadius(20))
                        }
                    }
                )
                .foregroundColor(isSelected ? .white : .primary)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }
}

// 项目行视图
struct ExerciseRow: View {
    let exercise: Exercise
    var onDelete: (() -> Void)?
    @State private var isPressed = false
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 删除背景
                if !exercise.isSystemPreset {
                    HStack(spacing: 0) {
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                offset = 0
                                isSwiped = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onDelete?()
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 16, weight: .medium))
                                Text("删除")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .frame(width: 72, height: 60)
                            .contentShape(Rectangle())
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.red.opacity(0.9),
                                            Color.red
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: Color.red.opacity(0.2), radius: 3, x: 0, y: 2)
                        )
                        .opacity(Double(abs(offset)) / 72.0)
                        .padding(.trailing, 4)
                    }
                    .frame(height: geometry.size.height)
                }
                
                // 主内容
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(exercise.name)
                            .font(.headline)
                        
                        HStack(spacing: 6) {
                            Text(exercise.category)
                            if let unit = exercise.unit, !unit.isEmpty {
                                Text("·")
                                Text(unit)
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.1))
                        )
                        .foregroundColor(.blue)
                        
                        Spacer()
                        
                        // 移除了点击删除按钮
                    }
                    
                    Text(exercise.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                .scaleEffect(isPressed ? 0.98 : 1)
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            if !exercise.isSystemPreset {
                                let newOffset = gesture.translation.width
                                if newOffset < -72 {
                                    let extraOffset = newOffset + 72
                                    offset = -72 + (extraOffset / 3)
                                } else {
                                    offset = max(-72, newOffset)
                                }
                            }
                        }
                        .onEnded { gesture in
                            if !exercise.isSystemPreset {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if gesture.translation.width < -20 {
                                        offset = -72
                                        isSwiped = true
                                    } else {
                                        offset = 0
                                        isSwiped = false
                                    }
                                }
                            }
                        }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
                .onTapGesture {
                    if isSwiped {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = 0
                            isSwiped = false
                        }
                    } else {
                        withAnimation {
                            isPressed = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isPressed = false
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 90)
    }
}

// 骨架屏
struct ExerciseRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 20)
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 16)
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 30)
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
    }
}

// 添加常见单位选项
private let commonUnits = ["kg", "次", "分钟", "秒", "米", "公里"]

// 修改添加项目表单
struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var exercises: [Exercise]
    @AppStorage("userId") private var userId: String = ""
    
    @State private var name = ""
    @State private var selectedCategory: String?
    @State private var description = ""
    @State private var notes = ""
    @State private var selectedUnit = "kg"
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @FocusState private var focusedField: Field?
    @State private var showSuccessAnimation = false
    @State private var saveSuccess = false
    @AppStorage("todayCreatedCount") private var todayCreatedCount: Int = 0
    @AppStorage("lastCreatedDate") private var lastCreatedDate: Double = Date().timeIntervalSince1970
    
    // 定义焦点字段
    private enum Field {
        case name
        case description
        case notes
    }
    
    private let categories = ["胸部", "背部", "腿部", "肩部", "手臂", "核心", "有氧"]
    private let commonUnits = ["kg", "次", "分钟", "秒", "米", "公里"]
    
    // 网格布局配置
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    
    var body: some View {
        NavigationView {
            ZStack {  // 添加 ZStack 来显示成功动画
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            // 名称输入
                            VStack(alignment: .leading, spacing: 6) {
                                Text("项目名称")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 16))
                                    TextField("例如：杠铃卧推", text: $name)
                                        .font(.system(size: 16))
                                        .focused($focusedField, equals: .name)
                                    
                                    if !name.isEmpty {
                                        Button(action: { name = "" }) {
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
                            .padding(.horizontal)
                            
                            // 类别选择
                            VStack(alignment: .leading, spacing: 8) {
                                Text("选择类别")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(categories, id: \.self) { category in
                                        CategoryCell(
                                            title: category,
                                            isSelected: selectedCategory == category,
                                            action: { selectedCategory = category }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                            
                            // 单位选择
                            VStack(alignment: .leading, spacing: 6) {
                                Text("选择单位")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Picker("", selection: $selectedUnit) {
                                    ForEach(commonUnits, id: \.self) { unit in
                                        Text(unit).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)  // 改用分段控制器样式
                            }
                            .padding(.horizontal)
                            
                            // 可选信息
                            VStack(alignment: .leading, spacing: 12) {
                                Text("详细信息（选填）")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                // 描述
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("描述")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if !description.isEmpty {
                                            Button(action: { description = "" }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.gray)
                                                    .font(.system(size: 16))
                                            }
                                        }
                                    }
                                    TextEditor(text: $description)
                                        .frame(height: 60)
                                        .padding(6)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                        .focused($focusedField, equals: .description)
                                        .id("description")  // 用于滚动定位
                                }
                                
                                // 注意事项
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("注意事项")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if !notes.isEmpty {
                                            Button(action: { notes = "" }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.gray)
                                                    .font(.system(size: 16))
                                            }
                                        }
                                    }
                                    TextEditor(text: $notes)
                                        .frame(height: 60)
                                        .padding(6)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                        .focused($focusedField, equals: .notes)
                                        .id("notes")  // 用于滚动定位
                                }
                            }
                            .padding(.horizontal)
                            
                            Spacer(minLength: 20)
                            
                            // 保存按钮
                            saveButton
                        }
                    }
                    .onChange(of: focusedField) { oldValue, newValue in
                        if newValue == .description {
                            withAnimation {
                                proxy.scrollTo("description", anchor: .center)
                            }
                        } else if newValue == .notes {
                            withAnimation {
                                proxy.scrollTo("notes", anchor: .center)
                            }
                        }
                    }
                }
                
                // 加载状态遮罩
                if isLoading {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                Text("保存中...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        )
                        .transition(.opacity)
                }
                
                // 成功动画
                if showSuccessAnimation {
                    SuccessAnimationView()
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isLoading)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showSuccessAnimation)
            .scrollDismissesKeyboard(.interactively)  // 允许滚动时收起键盘
            .navigationTitle("添加项目")
            .navigationBarItems(
                leading: Button("取消") { dismiss() }
                    .foregroundColor(.blue)
            )
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var saveButton: some View {
        Button(action: saveExercise) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text("保存中...")
                        .font(.system(size: 16, weight: .semibold))
                        .opacity(0.8)
                } else {
                    Text("保存")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(name.isEmpty || selectedCategory == nil ? Color.gray : Color.blue)
                    .shadow(color: (name.isEmpty || selectedCategory == nil ? Color.gray : Color.blue).opacity(0.3),
                            radius: 8, x: 0, y: 4)
            )
            .foregroundColor(.white)
            .opacity(isLoading ? 0.8 : 1)
            .scaleEffect(isLoading ? 0.98 : 1)
        }
        .disabled(name.isEmpty || selectedCategory == nil || isLoading)
        .padding(.horizontal)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isLoading)
    }
    
    private func saveExercise() {
        guard !name.isEmpty, let category = selectedCategory else { return }
        
        isLoading = true
        let now = Date()
        let exercise = Exercise(
            id: UUID().uuidString,
            name: name,
            category: category,
            description: description,
            notes: notes,
            isSystemPreset: false,
            unit: selectedUnit,
            createdAt: now,
            updatedAt: now,
            maxRecord: nil,  // 添加新字段，初始值为 nil
            lastRecordDate: nil  // 添加新字段，初始值为 nil
        )
        
        let db = Firestore.firestore()
        let exerciseData: [String: Any] = [
            "id": exercise.id,
            "name": exercise.name,
            "category": exercise.category,
            "description": exercise.description,
            "notes": exercise.notes,
            "isSystemPreset": exercise.isSystemPreset,
            "unit": exercise.unit ?? "",
            "createdAt": Timestamp(date: exercise.createdAt),
            "updatedAt": Timestamp(date: exercise.updatedAt),
            "maxRecord": NSNull(),  // 添加新字段
            "lastRecordDate": NSNull()  // 添加新字段
        ]
        
        db.collection("users")
            .document(userId)
            .collection("exercises")
            .document(exercise.id)
            .setData(exerciseData) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        isLoading = false
                        showError = true
                        errorMessage = "保存失败: \(error.localizedDescription)"
                    } else {
                        // 更新创建计数
                        todayCreatedCount += 1
                        lastCreatedDate = Date().timeIntervalSince1970
                        
                        showSuccessAnimation = true
                        exercises.append(exercise)
                        
                        if let encoded = try? JSONEncoder().encode(exercises) {
                            UserDefaults.standard.set(encoded, forKey: "cachedExercises")
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isLoading = false
                            dismiss()
                        }
                    }
                }
            }
    }
}

// 成功动画视图
struct SuccessAnimationView: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // 背景模糊效果
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 120, height: 120)
                .scaleEffect(scale)
                .opacity(opacity * 0.5)
            
            // 成功图标
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .opacity(opacity)
            
            // 成功文字
            Text("保存成功")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .offset(y: 60)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                scale = 1
                opacity = 1
                rotation = 360
            }
        }
    }
}

// 优化类别选择单元格样式
struct CategoryCell: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)  // 减小垂直内边距
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color(.systemGray6))
                        .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.clear,
                                radius: 4, x: 0, y: 2)
                )
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
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

#Preview {
    MaxRecordsView()
} 