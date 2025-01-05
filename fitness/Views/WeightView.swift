import SwiftUI
import Charts
import FirebaseFirestore
import UserNotifications

// 喝水记录模型
struct WaterIntakeRecord: Codable {
    let date: Date
    var cups: Int
    var lastUpdated: Date
    
    enum CodingKeys: String, CodingKey {
        case date
        case cups
        case lastUpdated
    }
}

struct WeightView: View {
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("userHeight") private var userHeight: Double = 0
    @State private var weightRecords: [WeightRecord] = []
    @State private var showingAddSheet = false
    @State private var showingHeightSheet = false
    @State private var newWeight = ""
    @State private var newHeight = ""
    @State private var selectedPeriod: TimePeriod = .week
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showingAnalysis = false
    @State private var weightGoal: Double?
    @State private var showingGoalSheet = false
    @State private var selectedMetric: WeightMetric = .weight
    @State private var restDays: [String] = []
    @State private var selectedHeight = 170 // 默认身高170cm
    @State private var recordToDelete: WeightRecord? // 用于删除确认
    @State private var showDeleteAlert = false // 用于显示删除确认对话框
    @State private var isHistoryExpanded = false  // 改为默认收起
    @State private var scrollToAnalysis = false
    @State private var showDeleteAllAlert = false
    @State private var chartPeriod: TimePeriod = .week
    @State private var analysisPeriod: TimePeriod = .week
    @AppStorage("lastSyncDate") private var lastSyncDate: Date = .distantPast
    @AppStorage("cachedWeightRecordsData") private var cachedWeightRecordsData: Data = Data()
    @State private var chartScrollPosition: CGFloat = 0
    @State private var chartScale: CGFloat = 1.0
    @State private var lastLoadTime: Date?
    @State private var chartDebouncer = Debouncer(delay: 0.3)
    @State private var weightDebouncer = Debouncer(delay: 0.3)
    @State private var heightDebouncer = Debouncer(delay: 0.3)
    @State private var periodDebouncer = Debouncer(delay: 0.3)
    @State private var isLoadingMore = false  // 是否正在加载更多
    @State private var hasMoreRecords = true  // 是否还有更多记录
    private let pageSize = 10  // 每页加载的记录数量
    
    private let maxDailyWeightRecords = 3  // 每日体重记录上限
    private let maxDailyHeightUpdates = 1  // 每日身高更新上限
    
    @State private var isRefreshing = false
    @State private var lastSyncTimeString: String = "未同步，下拉刷新"
    @State private var showSyncResult = false
    @State private var syncResultMessage = ""
    
    @State private var isTestMode = false  // 标记是否在使用测试数据
    
    @AppStorage("waterIntakeToday") private var waterIntakeToday: Int = 0
    @State private var showWaterAnimation: Bool = false
    private let dailyWaterGoal: Int = 7
    
    @AppStorage("lastWaterSync") private var lastWaterSync: Date = .distantPast
    
    @State private var showCompletionAnimation: Bool = false
    
    @AppStorage("waterNotificationsEnabled") private var waterNotificationsEnabled = false
    private let notificationInterval: TimeInterval = 2 * 60 * 60  // 2小时
    
    @State private var showStandardDeviationInfo = false
    
    @State private var showOfflineTestSheet = false
    
    @State private var isOfflineMode = false
    
    @State private var isOffline = false
    
    @State private var showHistory = false  // 修改初始值为 false，这样第一次打开时就是收起状态
    
    // 1. 添加状态变量（在 WeightView 结构体顶部）
    @State private var showDeleteSuccessToast = false
    @State private var deletedWeightValue: Double = 0
    @State private var showDeleteErrorToast = false
    
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    enum TimePeriod: String, CaseIterable {
        case week = "周"
        case month = "月"
        case threeMonths = "三个月"
        case year = "年"
        case all = "全部"
    }
    
    enum WeightMetric: String, CaseIterable {
        case weight = "体重"
        case bmi = "BMI"
    }
    
    // 添加趋势枚举
    enum WeightTrend {
        case up
        case down
        case stable
        case unknown
        
        var icon: String {
            switch self {
            case .up: return "arrow.up.circle.fill"
            case .down: return "arrow.down.circle.fill"
            case .stable: return "equal.circle.fill"
            case .unknown: return "minus.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .up: return .red
            case .down: return .green
            case .stable: return .blue
            case .unknown: return .gray
            }
        }
    }
    
    // 添加趋势计算函数
    private func calculateWeightTrend(for index: Int) -> (WeightTrend, Double) {
        // 如果是最后一条记录，返回未知状态
        guard index < weightRecords.count - 1 else { return (.unknown, 0) }
        
        let current = weightRecords[index].weight
        let next = weightRecords[index + 1].weight
        let difference = current - next
        
        let trend: WeightTrend
        if abs(difference) < 0.1 {  // 变化小于0.1kg视为持平
            trend = .stable
        } else if difference > 0 {
            trend = .up
        } else {
            trend = .down
        }
        
        return (trend, abs(difference))
    }
    
    // 在 WeightView 中添加
    @StateObject private var offlineManager = OfflineManager()
    @StateObject private var connectivityManager = ConnectivityManager()
    
    // 添加监听器引用
    private var waterIntakeListener: ListenerRegistration?
    
    // 将 waterIntakeListener 移到一个单独的 ObservableObject 类中
    @StateObject private var waterIntakeManager = WaterIntakeManager()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if userId.isEmpty {
                // 如果没有用户 ID，重定向到登录页面
                LoginView()
            } else {
                // 原有的导航视图内容
                NavigationView {
                    ScrollView {
                        if isLoading {
                            WeightViewSkeleton()  // 显示骨架屏
                                .transition(.opacity)
                        } else {
                            ScrollViewReader { proxy in
                                VStack(spacing: 20) {
                                    // 显示同步状态
                                    if showSyncResult {
                                        Text(syncResultMessage)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.top, 8)
                                    }
                                    
                                    Text(lastSyncTimeString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    // BMI 卡片
                                    bmiCard
                                    
                                    // 喝水卡片
                                    waterIntakeCard
                                    
                                    // 图表切换
                                    Picker("显示指标", selection: $selectedMetric) {
                                        ForEach(WeightMetric.allCases, id: \.self) { metric in
                                            Text(metric.rawValue).tag(metric)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                    
                                    // 图表区域
                                    chartSection
                                    
                                    // 目标进度卡片
                                    goalProgressCard
                                    
                                    // 统计分析部分
                                    analysisSection
                                        .id("analysis")
                                    
                                    // 记录列表
                                    recordsList
                                }
                                .padding()
                                .onChange(of: scrollToAnalysis) { oldValue, newValue in
                                    if newValue {
                                        withAnimation {
                                            proxy.scrollTo("analysis", anchor: .top)
                                        }
                                        // 重置状态
                                        scrollToAnalysis = false
                                    }
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.default, value: isLoading)
                    .refreshable {
                        await handleRefresh()
                    }
                    .navigationTitle("体重记录")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button(action: { showingAddSheet = true }) {
                                    Label("添加记录", systemImage: "plus")
                                }
                                Button(action: { showingGoalSheet = true }) {
                                    Label("设置目标", systemImage: "target")
                                }
                                Button(action: {
                                    withAnimation {
                                        scrollToAnalysis = true
                                    }
                                }) {
                                    Label("数据分析", systemImage: "chart.bar.xaxis")
                                }
                                
                                Divider()
                                
                                // 添加测试通知按钮
                                Button(action: testNotifications) {
                                    Label("测试喝水通知", systemImage: "drop.circle")
                                }
                                Button(action: testWeightNotifications) {
                                    Label("测试体重通知", systemImage: "scalemass.fill")  // 改用 scalemass.fill 替代 scale.circle
                                }
                                
                                Button(action: generateLocalTestData) {
                                    Label("生成测试数据", systemImage: "doc.badge.plus")
                                }
                                Button(action: clearLocalTestData) {
                                    Label("清除测试数据", systemImage: "trash")
                                        .foregroundColor(.red)
                                }
                                
                                Button(action: { showOfflineTestSheet = true }) {
                                    Label("测试离线功能", systemImage: "network.slash")
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("操作")
                                    Image(systemName: "ellipsis.circle.fill")
                                        .font(.title2)
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }
                    .sheet(isPresented: $showingAddSheet) {
                        addWeightSheet
                    }
                    .sheet(isPresented: $showingHeightSheet) {
                        heightInputSheet
                    }
                    .sheet(isPresented: $showingGoalSheet) {
                        goalWeightSheet
                    }
                    .sheet(isPresented: $showOfflineTestSheet) {
                        offlineTestSheet
                    }
                    .onAppear {
                        if shouldReload() {
                            isLoading = true  // 立即显示骨架屏
                            lastLoadTime = Date()
                            
                            // 先尝试加载缓存
                            let cachedRecords = loadFromCacheStorage()
                            if !cachedRecords.isEmpty {
                                DispatchQueue.main.async {
                                    self.weightRecords = cachedRecords
                                    self.isLoading = false
                                }
                            }
                            
                            // 然后异步加载最新数据
                            loadUserData()
                            loadWeightRecords()
                        }
                        // 检查并重置饮水量
                        checkAndResetWaterIntake()
                        // 加载今日喝水记录
                        loadTodayWaterIntake()
                        print("\n📱 检查喝水记录同步状态...")
                        // 如果距离上次同步超过5分钟，强制同步
                        if Date().timeIntervalSince(lastWaterSync) > 300 {
                            print("⚡️ 需要同步喝水记录")
                            updateWaterIntake()
                        } else {
                            print("✓ 喝水记录同步状态正常")
                        }
                        
                        // 请求通知权限并设置提醒
                        if !waterNotificationsEnabled {
                            requestNotificationPermission()
                        } else {
                            scheduleWaterReminders()
                        }
                        
                        // 添加通知监听
                        NotificationCenter.default.addObserver(
                            forName: NSNotification.Name("DrinkWaterAction"),
                            object: nil,
                            queue: .main
                        ) { _ in
                            if waterIntakeToday < dailyWaterGoal {
                                waterIntakeToday += 1
                                updateWaterIntake()
                            }
                        }
                        
                        // 设置体重记录提醒
                        scheduleWeightReminders()
                    }
                    .onChange(of: userHeight) { oldHeight, newHeight in
                        print("📊 身高数据更新: \(newHeight)cm")
                        // 这里可以添加需要随身高变化而更新的UI逻辑
                    }
                    .alert("加载失败", isPresented: $showError) {
                        Button("重试") {
                            loadWeightRecords()
                        }
                        Button("确定", role: .cancel) { }
                    } message: {
                        Text(errorMessage)
                    }
                    .alert("删除所有数据", isPresented: $showDeleteAllAlert) {
                        Button("取消", role: .cancel) { }
                        Button("删除", role: .destructive) {
                            deleteAllRecords { success in
                                if success {
                                    print("✅ 所有数据删除成功")
                                } else {
                                    print("❌ 删除数据失败")
                                    showError("删除数据失败")
                                }
                            }
                        }
                    } message: {
                        Text("确定要删除所有记录吗？此操作不可撤销。")
                    }
                    .onDisappear {
                        resetViewState()
                        waterIntakeManager.cleanup()
                    }
                    .overlay(
                        Group {
                            if isOffline {
                                HStack {
                                    Image(systemName: "wifi.slash")
                                    Text("离线模式")
                                }
                                .font(.caption)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(20)
                                .padding()
                            }
                        }
                        .animation(.default, value: isOffline),
                        alignment: .top
                    )
                    .overlay(alignment: .top) {
                        if showDeleteSuccessToast {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("\(deletedWeightValue, specifier: "%.1f")kg 记录已删除")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        if showDeleteErrorToast {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("删除失败，请重试")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .onChange(of: userId) { oldValue, newValue in
            if newValue.isEmpty {
                print("📱 用户已登出，清理数据...")
                // 清理数据
                waterIntakeManager.cleanup()
                weightRecords = []
                // 重置其他状态...
                
                // 重定向到登录页面
                dismiss()
            }
        }
    }
    
    // MARK: - 计算属性
    
    private func getFilteredRecords(for period: TimePeriod) -> [WeightRecord] {
        let calendar = Calendar.current
        let now = Date()
        
        switch period {
        case .week:
            return weightRecords.filter { calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 <= 7 }
        case .month:
            return weightRecords.filter { calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 <= 30 }
        case .threeMonths:
            return weightRecords.filter { calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 <= 90 }
        case .year:
            return weightRecords.filter { calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 <= 365 }
        case .all:
            return weightRecords
        }
    }
    
    // MARK: - UI Components
    
    private var bmiCard: some View {
        VStack(spacing: 15) {
            if let latestRecord = weightRecords.first {
                let bmi = calculateBMI(weight: latestRecord.weight)
                
                HStack(spacing: 20) {
                    // BMI 值显示
                    VStack(spacing: 8) {
                        Text("BMI")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f", bmi))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(getBMIColor(bmi: bmi))
                    }
                    
                    Divider()
                    
                    // 身高体重显示
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "ruler")
                            Text("\(Int(userHeight))cm")
                        }
                        HStack {
                            Image(systemName: "scalemass")
                            Text("\(latestRecord.weight, specifier: "%.1f")kg")
                        }
                    }
                    .foregroundColor(.secondary)
                }
                
                // BMI 状态显示
                Text(getBMIStatus(bmi: bmi))
                    .font(.headline)
                    .foregroundColor(getBMIColor(bmi: bmi))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(getBMIColor(bmi: bmi).opacity(0.1))
                    )
            } else {
                Text("暂无记录")
                    .foregroundColor(.secondary)
            }
            
            // 修改 bmiCard 中的按钮部分
            HStack(spacing: 20) {
                // 修改身高按钮
                Button(action: {
                    selectedHeight = Int(userHeight)
                    showingHeightSheet = true
                }) {
                    Label("修改身高", systemImage: "ruler")
                        .font(.footnote)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)  // 占据一半宽度
                }
                
                // 添加体重按钮
                Button(action: {
                    showingAddSheet = true
                }) {
                    Label("添加体重", systemImage: "plus.circle")
                        .font(.footnote)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)  // 占据一半宽度
                }
            }
            .padding(.top, 8)  // 增加一点上边距
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
    
    private var chartSection: some View {
        VStack {
            // 时间段选择器
            Picker("时间段", selection: $chartPeriod) {
                ForEach(TimePeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: chartPeriod) { _, newPeriod in
                periodDebouncer.debounce {
                    // 更新图表数据
                    updateChartData()
                }
            }
            
            // 修改图表部分
            ScrollView(.horizontal, showsIndicators: false) {
                Chart {
                    ForEach(chartData) { record in
                        LineMark(
                            x: .value("日期", record.date),
                            y: .value(selectedMetric.rawValue, 
                                    selectedMetric == .weight ? record.weight : calculateBMI(weight: record.weight))
                        )
                        .foregroundStyle(Color.blue)
                        PointMark(
                            x: .value("日期", record.date),
                            y: .value(selectedMetric.rawValue, 
                                    selectedMetric == .weight ? record.weight : calculateBMI(weight: record.weight))
                        )
                        .foregroundStyle(Color.blue)
                    }
                    
                    // BMI 参考线
                    if selectedMetric == .bmi {
                        RuleMark(y: .value("偏瘦", 18.5))
                            .foregroundStyle(.orange.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [5, 5]))
                        RuleMark(y: .value("正常", 24))
                            .foregroundStyle(.green.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [5, 5]))
                        RuleMark(y: .value("偏胖", 28))
                            .foregroundStyle(.red.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [5, 5]))
                    }
                }
                .chartXAxis {
                    let values = getAxisValues(for: chartPeriod)
                    
                    AxisMarks(values: values) { value in
                        if let date = value.as(Date.self) {
                            let format = getDateFormat(for: chartPeriod)
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                Text(date.formatted(format))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(width: getChartWidth(for: chartPeriod, recordCount: chartData.count))
                .frame(height: 200)
                .padding()
            }
            
            // Y轴标签
            Text(selectedMetric == .weight ? "体重 (kg)" : "BMI")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func getDateRange(for period: TimePeriod) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date
        
        switch period {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .all:
            if let firstRecord = weightRecords.last {
                startDate = firstRecord.date
            } else {
                startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            }
        }
        
        return startDate...now
    }
    
    // 在 WeightStats 结构体中添加更多统计指标
    struct WeightStats {
        let average: Double
        let maxChange: Double
        let highest: Double
        let lowest: Double
        let weeklyAverage: Double
        let monthlyAverage: Double
        let weeklyChange: Double
        let monthlyChange: Double
        let standardDeviation: Double
    }
    
    // 修改统计计算函数
    private func calculateStats(for records: [WeightRecord]) -> WeightStats {
        let calendar = Calendar.current
        let now = Date()
        
        // 获取不同时间段的记录
        let weekRecords = records.filter { 
            calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 <= 7 
        }
        let monthRecords = records.filter { 
            calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 <= 30 
        }
        
        // 基本统计
        let weights = records.map { $0.weight }
        let average = weights.reduce(0, +) / Double(weights.count)
        let highest = weights.max() ?? 0
        let lowest = weights.min() ?? 0
        
        // 周平均和月平均
        let weeklyAverage = weekRecords.map { $0.weight }.reduce(0, +) / Double(max(weekRecords.count, 1))
        let monthlyAverage = monthRecords.map { $0.weight }.reduce(0, +) / Double(max(monthRecords.count, 1))
        
        // 周变化和月变化
        let weeklyChange = weekRecords.first?.weight ?? 0 - (weekRecords.last?.weight ?? 0)
        let monthlyChange = monthRecords.first?.weight ?? 0 - (monthRecords.last?.weight ?? 0)
        
        // 标准差计算
        let variance = weights.map { pow($0 - average, 2) }.reduce(0, +) / Double(weights.count)
        let standardDeviation = sqrt(variance)
        
        // 最大变化
        var maxChange = 0.0
        for i in 0..<weights.count-1 {
            let change = abs(weights[i] - weights[i+1])
            maxChange = max(maxChange, change)
        }
        
        return WeightStats(
            average: average,
            maxChange: maxChange,
            highest: highest,
            lowest: lowest,
            weeklyAverage: weeklyAverage,
            monthlyAverage: monthlyAverage,
            weeklyChange: weeklyChange,
            monthlyChange: monthlyChange,
            standardDeviation: standardDeviation
        )
    }
    
    // 修改分析部分的视图
    private var analysisSection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("数据分析")
                    .font(.headline)
                Spacer()
                Picker("分析周期", selection: $analysisPeriod) {
                    ForEach(TimePeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
            }
            
            if !weightRecords.isEmpty {
                // 使用与图表相同的过滤方法获取对应时间段的记录
                let filteredRecords = getFilteredRecords(for: analysisPeriod)
                let stats = calculateStats(for: filteredRecords)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 15) {
                    // 基本统计
                    StatCard(title: "平均体重", value: stats.average, unit: "kg")
                    StatCard(title: "最大变化", value: stats.maxChange, unit: "kg")
                    StatCard(title: "最高体重", value: stats.highest, unit: "kg")
                    StatCard(title: "最低体重", value: stats.lowest, unit: "kg")
                    
                    // 周期统计
                    StatCard(title: "周平均", value: stats.weeklyAverage, unit: "kg")
                    StatCard(title: "月平均", value: stats.monthlyAverage, unit: "kg")
                    
                    // 变化趋势
                    StatCard(
                        title: "周变化", 
                        value: stats.weeklyChange,
                        unit: "kg"
                    )
                    .foregroundColor(stats.weeklyChange > 0 ? .red : .green)
                    
                    StatCard(
                        title: "月变化", 
                        value: stats.monthlyChange,
                        unit: "kg"
                    )
                    .foregroundColor(stats.monthlyChange > 0 ? .red : .green)
                    
                    // 波动指标
                    StatCard(title: "标准差", value: stats.standardDeviation, unit: "kg")
                        .overlay(
                            Button(action: {
                                showStandardDeviationInfo = true
                            }) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                            }
                            .offset(x: -10, y: -10),
                            alignment: .topTrailing
                        )
                }
            } else {
                Text("暂无数据")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .alert("什么是标准差？", isPresented: $showStandardDeviationInfo) {
            Button("了解", role: .cancel) { }
        } message: {
            Text("标准差反映了体重波动的程度。数值越小，表示体重越稳定；数值越大，表示体重波动越大。")
        }
    }
    
    private func loadRestDays() {
        let db = Firestore.firestore()
        db.collection("users")
            .document(userId)
            .collection("calendar")
            .document("restDays")
            .getDocument { snapshot, error in
                if let error = error {
                    print("Error loading rest days: \(error)")
                    return
                }
                
                if let data = snapshot?.data(),
                   let days = data["days"] as? [String] {
                    self.restDays = days
                }
            }
    }
    
    private func setRestDay(date: Date) {
        let dateString = dateFormatter.string(from: date)
        
        // 如果已经是休息日，则移除
        if restDays.contains(dateString) {
            restDays.removeAll { $0 == dateString }
        } else {
            restDays.append(dateString)
        }
        
        // 更新 Firestore
        let db = Firestore.firestore()
        db.collection("users")
            .document(userId)
            .collection("calendar")
            .document("restDays")
            .setData([
                "days": restDays
            ]) { error in
                if let error = error {
                    print("Error setting rest day: \(error)")
                }
            }
    }
    
    private var goalProgressCard: some View {
        VStack(spacing: 10) {
            // 添加标题和设置按钮
            HStack {
                Text("目标进度")
                    .font(.headline)
                Spacer()
                Button(action: { showingGoalSheet = true }) {
                    Label("设置目标", systemImage: "target")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            if let goal = weightGoal,
               let currentWeight = weightRecords.first?.weight {
                let difference = goal - currentWeight
                let isGainMode = goal > currentWeight  // 判断是增重还是减重模式
                
                HStack {
                    // 当前体重
                    VStack(alignment: .leading, spacing: 5) {
                        Text("当前体重")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(currentWeight, specifier: "%.1f")kg")
                            .font(.title3)
                    }
                    
                    Divider()
                    
                    // 目标体重
                    VStack(alignment: .leading, spacing: 5) {
                        Text("目标体重")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(goal, specifier: "%.1f")kg")
                            .font(.title3)
                    }
                    
                    Divider()
                    
                    // 差距
                    VStack(alignment: .leading, spacing: 5) {
                        Text("差距")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(abs(difference), specifier: "%.1f")kg")
                            .font(.title3)
                            .foregroundColor(isGainMode ? .blue : .green)
                    }
                    
                    // 预估完成时间
                    if let estimatedDays = calculateEstimatedDays(
                        currentWeight: currentWeight,
                        goalWeight: goal,
                        weightRecords: weightRecords
                    ) {
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("预计完成")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(estimatedDays)天")
                                .font(.title3)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                // 修复进度计算
                let progress: Double = {
                    let totalDifference = abs(goal - currentWeight)
                    let startWeight = weightRecords.last?.weight ?? currentWeight
                    let currentDifference = abs(currentWeight - startWeight)
                    
                    // 如果目标差距为0，返回0进度
                    guard totalDifference > 0 else { return 0 }
                    
                    // 根据目标方向计算进度
                    if isGainMode {
                        return currentWeight > startWeight ? 
                            min(currentDifference / totalDifference, 1.0) : 0
                    } else {
                        return currentWeight < startWeight ? 
                            min(currentDifference / totalDifference, 1.0) : 0
                    }
                }()
                
                ProgressView(value: progress)
                    .tint(isGainMode ? .blue : .green)
                
                Text("\(progress * 100, specifier: "%.1f")% 完成")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("尚未设置目标体重")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
    
    private var recordsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题栏带折叠按钮
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {  // 添加动画
                    isHistoryExpanded.toggle()
                }
            }) {
                HStack {
                    Text("历史记录")
                        .font(.headline)
                    Spacer()
                    Image(systemName: isHistoryExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            
            if isHistoryExpanded {
                if weightRecords.isEmpty {
                    EmptyStateView(action: {
                        showingAddSheet = true
                    })
                    .transition(.opacity)
                    .animation(.easeInOut, value: weightRecords.isEmpty)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(weightRecords.enumerated()), id: \.element.id) { index, record in
                            let (trend, difference) = calculateWeightTrend(for: index)
                            WeightRecordRow(
                                record: record,
                                trend: trend,
                                difference: difference,
                                onDelete: {
                                    recordToDelete = record
                                    showDeleteAlert = true
                                }
                            )
                        }
                        
                        // 加载更多
                        if hasMoreRecords {
                            Button(action: loadMoreRecords) {
                                if isLoadingMore {
                                    ProgressView()
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding()
                                } else {
                                    Text("加载更多")
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding()
                                }
                            }
                            .disabled(isLoadingMore)
                        }
                    }
                }
            }
        }
        .padding()
        .animation(.default, value: weightRecords)  // 保持数据更新的动画
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let record = recordToDelete {
                    deleteRecord(record)
                }
            }
        } message: {
            Text("确定要删除这条记录吗？此操作不可撤销。")
        }
    }
    
    // 添加记录行组件
    private struct WeightRecordRow: View {
        let record: WeightRecord
        let trend: WeightTrend
        let difference: Double
        let onDelete: () -> Void
        
        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(record.weight, specifier: "%.1f") kg")
                            .font(.headline)
                        
                        // 添加趋势指示
                        if trend != .unknown {
                            Image(systemName: trend.icon)
                                .foregroundColor(trend.color)
                                .font(.subheadline)
                            if difference > 0 {
                                Text("\(difference, specifier: "%.1f")kg")
                                    .font(.caption)
                                    .foregroundColor(trend.color)
                            }
                        }
                    }
                    
                    Text(record.date.formatted(.dateTime.month().day()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 2. 修改 WeightRecordRow 中的删除按钮
                Button(action: {
                    // 添加触觉反馈
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    
                    onDelete()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .opacity(0.7)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
        }
    }
    
    private var addWeightSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("添加体重记录")
                    .font(.headline)
                    .padding(.top)
                
                // 使用滚轮选择器
                HStack {
                    // 整数部分选择器，从最近体重开始
                    Picker("", selection: Binding(
                        get: { 
                            if let weight = Double(newWeight) {
                                let decimal = weight.truncatingRemainder(dividingBy: 1)
                                return Int(weight - decimal)
                            }
                            // 使用最近的体重记录作为初始值
                            if let lastWeight = weightRecords.first?.weight {
                                return Int(lastWeight)
                            }
                            return 70  // 默认值
                        },
                        set: { newValue in
                            if let weight = Double(newWeight) {
                                let decimal = weight.truncatingRemainder(dividingBy: 1)
                                newWeight = String(Double(newValue) + decimal)
                            } else {
                                newWeight = String(newValue)
                            }
                        }
                    )) {
                        ForEach(30...200, id: \.self) { num in
                            Text("\(num)").tag(num)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 60)
                    
                    Text(".")
                        .font(.title2)
                    
                    // 小数部分选择器
                    Picker("", selection: Binding(
                        get: { 
                            if let weight = Double(newWeight) {
                                return Int(weight.truncatingRemainder(dividingBy: 1) * 10)
                            }
                            return 0
                        },
                        set: { newValue in
                            if let weight = Double(newWeight) {
                                let integer = Int(weight)
                                newWeight = String(Double(integer) + Double(newValue) / 10)
                            }
                        }
                    )) {
                        ForEach(0...9, id: \.self) { num in
                            Text("\(num)").tag(num)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 60)
                    
                    Text("kg")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                if let weight = Double(newWeight) {
                    Text("BMI: \(calculateBMI(weight: weight), specifier: "%.1f")")
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    if let weightValue = Double(newWeight) {
                        addWeightRecord(weightValue)
                        showingAddSheet = false
                        newWeight = ""
                    }
                }) {
                    Text("保存")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
                
                Spacer()
            }
            .navigationBarItems(trailing: Button("取消") {
                showingAddSheet = false
            })
        }
        .onAppear {
            // 设置初始值为最近的体重记录
            if newWeight.isEmpty {
                if let lastWeight = weightRecords.first?.weight {
                    newWeight = String(format: "%.1f", lastWeight)
                } else {
                    newWeight = "70.0"  // 默认值
                }
            }
        }
    }
    
    private var heightInputSheet: some View {
        NavigationView {
            VStack {
                Text("选择身高")
                    .font(.headline)
                    .padding()
                
                HStack {
                    Picker("", selection: $selectedHeight) {
                        ForEach(100...220, id: \.self) { height in
                            Text("\(height)").tag(height)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                    
                    Text("厘米")
                        .foregroundColor(.secondary)
                }
                .padding()
                
                Button(action: {
                    updateUserHeight(Double(selectedHeight))
                    showingHeightSheet = false
                }) {
                    Text("确定")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("设置身高")
            .navigationBarItems(trailing: Button("取消") {
                showingHeightSheet = false
            })
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadWeightRecords(isLoadingMore: Bool = false) {
        if !isLoadingMore {
            isLoading = true
        }
        
        let db = Firestore.firestore()
        var query = db.collection("users")
            .document(userId)
            .collection("weightRecords")
            .order(by: "date", descending: true)
        
        // 添加分页和时间范围限制
        if isLoadingMore {
            if let lastRecord = weightRecords.last {
                query = query.start(after: [lastRecord.date])
            }
        } else {
            // 只加载最近一年的数据
            let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
            query = query.whereField("date", isGreaterThan: oneYearAgo)
        }
        
        // 限制每次查询的数量
        query = query.limit(to: pageSize)
        
        // 执行查询
        query.getDocuments { snapshot, error in
            if let error = error {
                print("❌ 加载失败: \(error)")
                DispatchQueue.main.async {
                    self.showError("加载记录失败")
                    self.isLoadingMore = false
                }
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("⚠️ 未找到记录")
                DispatchQueue.main.async {
                    self.hasMoreRecords = false
                    self.isLoadingMore = false
                }
                return
            }
            
            let newRecords = documents.compactMap { doc -> WeightRecord? in
                guard let weight = doc.data()["weight"] as? Double,
                      let date = (doc.data()["date"] as? Timestamp)?.dateValue()
                else { return nil }
                
                return WeightRecord(
                    id: doc.documentID,
                    userId: self.userId,
                    weight: weight,
                    date: date
                )
            }
            
            DispatchQueue.main.async {
                if isLoadingMore {
                    self.weightRecords.append(contentsOf: newRecords)
                } else {
                    self.weightRecords = newRecords
                    self.isLoading = false
                }
                
                self.hasMoreRecords = documents.count == self.pageSize
                self.isLoadingMore = false
                self.saveToCacheStorage(self.weightRecords)
            }
            
            print("✅ 加载了 \(newRecords.count) 条记录")
        }
    }
    
    // 修改缓存设置函数
    private func setupFirestoreCache() {
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        let db = Firestore.firestore()
        db.settings = settings
    }
    
    // 添加加载更多函数
    private func loadMoreRecords() {
        guard !isLoadingMore && hasMoreRecords else { return }
        isLoadingMore = true
        
        if isTestMode {
            loadMoreTestRecords()
        } else {
            loadMoreRealRecords()
        }
    }
    
    // 分离测试数据的加载
    private func loadMoreTestRecords() {
        if let data = UserDefaults.standard.data(forKey: "testWeightRecords"),
           let allRecords = try? JSONDecoder().decode([WeightRecord].self, from: data) {
            
            let currentCount = weightRecords.count
            let nextBatch = Array(allRecords[currentCount..<min(currentCount + pageSize, allRecords.count)])
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.weightRecords.append(contentsOf: nextBatch)
                self.hasMoreRecords = currentCount + pageSize < allRecords.count
                self.isLoadingMore = false
                print("📝 加载了 \(nextBatch.count) 条测试记录")
            }
        }
    }
    
    // 分离实际数据的加载
    private func loadMoreRealRecords() {
        loadWeightRecords(isLoadingMore: true)
    }
    
    private func syncWeightRecords() {
        // 先处理离线队列
        offlineManager.processPendingOperations { success in
            if success {
                // 清除已处理的操作
                self.offlineManager.clearProcessedOperations()
            }
            
            // 继续正常的同步流程
            self.performNormalSync()
        }
    }
    
    private func performNormalSync() {
        print("\n🔄 开始同步数据...")
        print("⏰ 当前时间: \(Date())")
        isLoading = true
        
        let db = Firestore.firestore()
        // 获取3个月前的日期
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        print("📅 同步范围: \(threeMonthsAgo) 至今")
        
        db.collection("users")
            .document(userId)
            .collection("weightRecords")
            .whereField("date", isGreaterThan: Timestamp(date: threeMonthsAgo))
            .order(by: "date", descending: true)
            .getDocuments { snapshot, error in
                // 创建一个函数来在主线程更新状态
                let updateState = { (records: [WeightRecord]) in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.weightRecords = records
                        self.saveToCacheStorage(records)
                        self.lastSyncDate = Date()
                        print("✅ 同步完成，缓存了 \(records.count) 条记录")
                    }
                }
                
                if let error = error {
                    print("\n❌ 同步失败:")
                    print("  - 错误类型: \(error.localizedDescription)")
                    if error.localizedDescription.contains("Resource exhausted") {
                        print("  - 原因: Firestore 配额限制")
                        print("  - 建议: 等到明天再尝试同步")
                        // 如果是配额限制，使用缓存数据
                        let cachedRecords = loadFromCacheStorage()
                        if !cachedRecords.isEmpty {
                            print("  - 使用缓存数据代替")
                            weightRecords = cachedRecords
                        }
                    }
                    DispatchQueue.main.async {
                        self.showError("同步记录失败")
                        self.isLoading = false
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("⚠️ 未找到记录")
                    updateState([])
                    return
                }
                
                print("📊 同步到 \(documents.count) 条记录")
                
                let records = documents.compactMap { doc -> WeightRecord? in
                    guard let weight = doc.data()["weight"] as? Double,
                          let date = (doc.data()["date"] as? Timestamp)?.dateValue()
                    else {
                        print("⚠️ 记录格式错误: \(doc.documentID)")
                        return nil
                    }
                    
                    return WeightRecord(
                        id: doc.documentID,
                        userId: self.userId,
                        weight: weight,
                        date: date
                    )
                }
                
                updateState(records)
            }
    }
    
    private func addWeightRecord(_ weight: Double) {
        let newRecord = WeightRecord(
            id: UUID().uuidString,
            userId: userId,
            weight: weight,
            date: Date()
        )
        
        // 先更新本地UI
        weightRecords.insert(newRecord, at: 0)
        saveToCacheStorage(weightRecords)
        
        // 检查网络连接
        Task {
            let hasConnection = await checkDatabaseConnection()
            if hasConnection {
                // 有网络，直接添加
                self.addRecordToFirestore(newRecord)
            } else {
                // 无网络，加入离线队列
                self.offlineManager.addOperation(type: .add, record: newRecord)
                // 显示离线提示
                self.showOfflineAlert()
            }
        }
    }
    
    private func calculateBMI(weight: Double) -> Double {
        guard userHeight > 0 else { return 0 }
        let heightInMeters = userHeight / 100
        let bmi = weight / (heightInMeters * heightInMeters)
        return round(bmi * 10) / 10 // 保留一位小数
    }
    
    private func getBMIStatus(bmi: Double) -> String {
        switch bmi {
        case ..<18.5:
            return "体重偏轻"
        case 18.5..<24.9:
            return "体重正常"
        case 24.9..<29.9:
            return "体重偏重"
        default:
            return "肥胖"
        }
    }
    
    private func getBMIColor(bmi: Double) -> Color {
        switch bmi {
        case ..<18.5:
            return .orange
        case 18.5..<24.9:
            return .green
        case 24.9..<29.9:
            return .orange
        default:
            return .red
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showError = true
        }
    }
    
    private func updateUserHeight(_ height: Double) {
        print("🔄 开始更新身高: \(height)cm")
        
        // 检查每日限制
        guard checkDailyHeightLimit() else {
            DispatchQueue.main.async {
                self.showError("今日身高更新已达上限(每日1次)")
                self.showingHeightSheet = false
            }
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users").document(userId).updateData([
            "height": height,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("❌ 更新身高失败: \(error)")
                self.showError("更新身高失败")
                return
            }
            
            // 在主线程更新UI
            DispatchQueue.main.async {
                self.userHeight = height
                // 记录最后更新时间
                UserDefaults.standard.set(Date(), forKey: "lastHeightUpdateDate")
                print("✅ 身高更新成功: \(height)cm")
            }
        }
    }
    
    private func loadUserData() {
        print("\n========== 开始加载用户数据 ==========")
        
        let db = Firestore.firestore()
        db.collection("users")
            .document(userId)
            .getDocument { snapshot, error in
                if let error = error {
                    print("❌ 加载失败: \(error)")
                    return
                }
                
                if let data = snapshot?.data() {
                    print("\n📝 用户基本信息:")
                    
                    // 更新身高
                    if let height = data["height"] as? Double {
                        print("  - height: \(height)")
                        DispatchQueue.main.async {
                            self.userHeight = height
                        }
                    }
                    
                    // 更新目标体重
                    if let goal = data["weightGoal"] as? Double {
                        print("  - weightGoal: \(goal)")
                        DispatchQueue.main.async {
                            self.weightGoal = goal
                        }
                    }
                    
                    print("  - lastWeight: \(data["lastWeight"] ?? "未设置")")
                    if let lastWeightDate = data["lastWeightDate"] as? Timestamp {
                        print("  - lastWeightDate: \(lastWeightDate.dateValue())")
                    }
                    print("  - name: \(data["name"] ?? "未设置")")
                    
                    if let history = data["weightHistory"] as? [[String: Any]],
                       history.count < self.weightRecords.count {
                        print("📊 检测到本地记录数量大于历史记录，开始同步...")
                        self.syncLocalToHistory()
                    }
                    
                    if let history = data["weightHistory"] as? [[String: Any]] {
                        print("\n📊 体重历史记录: \(history.count) 条")
                        for (index, record) in history.enumerated() {
                            if index < 3 {  // 只显示前3条记录
                                print("  记录 #\(index + 1):")
                                print("    - weight: \(record["weight"] ?? "未设置")")
                                if let date = record["date"] as? Timestamp {
                                    print("    - date: \(date.dateValue())")
                                }
                                print("    - recordId: \(record["recordId"] ?? "未设置")")
                            }
                        }
                        if history.count > 3 {
                            print("  ...(还有 \(history.count - 3) 条记录)")
                        }
                    } else {
                        print("❌ weightHistory 不存在或格式错误")
                    }
                } else {
                    print("❌ 未找到用户文档")
                }
                
                print("\n========== 测试结束 ==========")
            }
    }
    
    private func checkAndCreateUpdates(_ data: [String: Any]) -> [String: Any] {
        var updates: [String: Any] = [:]
        
        // 检查身高字段
        if data["height"] == nil {
            updates["height"] = 170.0
        }
        
        // 检查目标体重字段
        if data["weightGoal"] == nil {
            updates["weightGoal"] = 75.0
        }
        
        // 检查最后一次体重字段
        if data["lastWeight"] == nil {
            if let firstRecord = weightRecords.first {
                updates["lastWeight"] = firstRecord.weight
                updates["lastWeightDate"] = Timestamp(date: firstRecord.date)
            }
        }
        
        // 添加更新时间
        updates["updatedAt"] = FieldValue.serverTimestamp()
        
        return updates
    }
    
    private func createNewUserData() {
        let db = Firestore.firestore()
        let now = Date()
        let defaultWeight = 75.0
        
        // 创建初始历史记录
        let initialHistory: [String: Any] = [
            "weight": defaultWeight,
            "date": Timestamp(date: now),
            "recordId": "initial"
        ]
        
        let userData: [String: Any] = [
            "height": 170.0,
            "weightGoal": defaultWeight,
            "lastWeight": defaultWeight,
            "lastWeightDate": Timestamp(date: now),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "name": "用户\(userId.prefix(6))",
            "weightHistory": [initialHistory]
        ]
        
        db.collection("users").document(userId).setData(userData) { error in
            if let error = error {
                print("❌ 创建用户数据失败: \(error)")
                return
            }
            print("✅ 创建用户数据成功")
            
            // 更新本地数据
            DispatchQueue.main.async {
                self.userHeight = 170.0
                self.weightGoal = 75.0
                // 添加初始体重记录
                self.addWeightRecord(75.0)
            }
        }
    }
    
    private func updateLocalData(from data: [String: Any]) {
        DispatchQueue.main.async {
            // 更新身高
            if let height = data["height"] as? Double {
                print("✅ 找到身高数据: \(height)cm")
                self.userHeight = height
            }
            
            // 更新目标体重
            if let goal = data["weightGoal"] as? Double {
                print("✅ 找到目标体重: \(goal)kg")
                self.weightGoal = goal
            }
            
            // 更新最后一次体重记录
            if let lastWeight = data["lastWeight"] as? Double,
               let lastWeightDate = (data["lastWeightDate"] as? Timestamp)?.dateValue() {
                print("✅ 找到最后一次体重记录: \(lastWeight)kg (\(lastWeightDate))")
            }
        }
    }
    
    private func formatYAxisValue(_ value: Double) -> String {
        if selectedMetric == .weight {
            return String(format: "%.1f kg", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
    
    private var goalWeightSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("设置目标体重")
                    .font(.headline)
                    .padding(.top)
                
                // 使用滚轮选择器
                HStack {
                    Picker("", selection: Binding(
                        get: { Int(weightGoal ?? (weightRecords.first?.weight ?? 70)) },
                        set: { newValue in
                            weightGoal = Double(newValue)
                        }
                    )) {
                        ForEach(30...200, id: \.self) { num in
                            Text("\(num)").tag(num)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 60)
                    
                    Text(".")
                        .font(.title2)
                    
                    Picker("", selection: Binding(
                        get: { 
                            if let goal = weightGoal {
                                return Int(goal.truncatingRemainder(dividingBy: 1) * 10)
                            }
                            return 0
                        },
                        set: { newValue in
                            if let goal = weightGoal {
                                let integer = Int(goal)
                                weightGoal = Double(integer) + Double(newValue) / 10
                            }
                        }
                    )) {
                        ForEach(0...9, id: \.self) { num in
                            Text("\(num)").tag(num)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 60)
                    
                    Text("kg")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                Button(action: {
                    if let goal = weightGoal {
                        updateWeightGoal(goal)
                        showingGoalSheet = false
                    }
                }) {
                    Text("保存")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
                
                Spacer()
            }
            .navigationBarItems(trailing: Button("取消") {
                showingGoalSheet = false
            })
        }
        .onAppear {
            // 如果没有设置目标，使用当前体重作为初始值
            if weightGoal == nil {
                weightGoal = weightRecords.first?.weight ?? 70
            }
        }
    }
    
    private func updateWeightGoal(_ goal: Double) {
        guard let goal = weightGoal else { return }
        
        let db = Firestore.firestore()
        db.collection("users")
            .document(userId)
            .updateData([
                "weightGoal": goal
            ]) { error in
                if let error = error {
                    print("❌ 保存目标体重失败: \(error)")
                    showError("保存目标体重失败")
                    return
                }
                
                print("✅ 目标体重保存成功: \(goal)kg")
                showingGoalSheet = false
            }
    }
    
    private func deleteRecord(_ record: WeightRecord) {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // 1. 删除记录文档
        let recordRef = db.collection("users")
            .document(userId)
            .collection("weightRecords")
            .document(record.id)
        
        batch.deleteDocument(recordRef)
        
        // 2. 从历史记录中移除
        let userRef = db.collection("users").document(userId)
        let weightHistory: [String: Any] = [
            "weight": record.weight,
            "date": Timestamp(date: record.date),
            "recordId": record.id
        ]
        
        batch.updateData([
            "weightHistory": FieldValue.arrayRemove([weightHistory]),
            "updatedAt": FieldValue.serverTimestamp()
        ] as [String: Any], forDocument: userRef)
        
        // 3. 执行批量操作
        batch.commit { error in
            if let error = error {
                print("❌ 删除记录失败: \(error)")
                // 失败时显示错误提示
                DispatchQueue.main.async {
                    withAnimation {
                        self.showDeleteErrorToast = true
                    }
                    // 3秒后隐藏提示
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.showDeleteErrorToast = false
                        }
                    }
                }
                return
            }
            
            print("✅ 记录删除成功")
            DispatchQueue.main.async {
                self.weightRecords.removeAll { $0.id == record.id }
                self.saveToCacheStorage(self.weightRecords)
                self.lastSyncDate = Date()
                
                // 成功时显示成功提示
                self.deletedWeightValue = record.weight
                withAnimation {
                    self.showDeleteSuccessToast = true
                }
                // 3秒后隐藏提示
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        self.showDeleteSuccessToast = false
                    }
                }
            }
        }
    }

    private func addTestDataForYear() {
        print("🔄 开始生成测试数据...")
        
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .year, value: -1, to: now)!
        
        // 生成随机日期和体重数据
        var testRecords: [(Date, Double)] = []
        var currentDate = startDate
        let baseWeight = 75.0
        var currentWeight = baseWeight
        
        // 每月只生成2-3条记录
        while currentDate <= now {
            let daysInMonth = calendar.range(of: .day, in: .month, for: currentDate)?.count ?? 30
            let recordDays = Array(1...daysInMonth).shuffled()[0..<Int.random(in: 2...3)]
            
            for _ in recordDays.sorted() {
                if let date = calendar.date(bySettingHour: Int.random(in: 6...22),
                                          minute: Int.random(in: 0...59),
                                          second: 0,
                                          of: currentDate) {
                    let randomChange = Double.random(in: -1.0...1.0)
                    currentWeight += randomChange
                    currentWeight = min(max(currentWeight, baseWeight - 5), baseWeight + 5)
                    testRecords.append((date, round(currentWeight * 10) / 10))
                }
            }
            
            currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? now
        }
        
        // 按日期排序
        testRecords.sort { $0.0 < $1.0 }
        
        print("📊 生成了 \(testRecords.count) 条测试数据，准备分批保存...")
        
        // 将数据分成更小的批次（每批3条记录）
        let batchSize = 3
        let batches = stride(from: 0, to: testRecords.count, by: batchSize).map {
            Array(testRecords[$0..<min($0 + batchSize, testRecords.count)])
        }
        
        print("📊 将数据分成 \(batches.count) 批，每批 \(batchSize) 条记录")
        
        // 开始处理第一批
        processBatch(0, batches: batches)
    }
    
    private func addTestRecords(_ records: [(Date, Double)], retryCount: Int = 3, completion: @escaping (Bool) -> Void) {
        print("📝 开始添加一批测试数据...(剩余重试次数: \(retryCount))")
        print("📊 准备添加 \(records.count) 条记录")
        
        let db = Firestore.firestore()
        let batch = db.batch()
        var newRecords: [WeightRecord] = []
        
        for (index, (date, weight)) in records.enumerated() {
            let docRef = db.collection("users")
                .document(userId)
                .collection("weightRecords")
                .document()
            
            print("📌 准备第 \(index + 1) 条记录: \(date) - \(weight)kg")
            
            batch.setData([
                "weight": weight,
                "date": Timestamp(date: date),
                "userId": userId
            ], forDocument: docRef)
            
            newRecords.append(WeightRecord(
                id: docRef.documentID,
                userId: userId,
                weight: weight,
                date: date
            ))
        }
            
        print("⏳ 开始执行批量添加...")
        batch.commit { error in
            if let error = error {
                print("❌ 添加测试数据失败: \(error)")
                
                if error.localizedDescription.contains("Resource exhausted") && retryCount > 0 {
                    print("⚠️ 遇到配额限制，等待15秒后重试...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                        self.addTestRecords(records, retryCount: retryCount - 1, completion: completion)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.showError("添加测试数据失败")
                    completion(false)
                }
                return
            }
            
            print("✅ 成功保存这批测试数据")
            let updatedRecords = self.weightRecords + newRecords
            DispatchQueue.main.async {
                self.weightRecords = updatedRecords.sorted(by: { $0.date > $1.date })
                self.saveToCacheStorage(self.weightRecords)
                print("✅ 本地数据更新完成，现有 \(self.weightRecords.count) 条记录")
                completion(true)
            }
        }
    }
    
    private func processBatch(_ index: Int, batches: [[(Date, Double)]]) {
        guard index < batches.count else {
            print("✅ 所有批次处理完成")
            return
        }
        
        let batch = batches[index]
        print("📦 开始处理第 \(index + 1)/\(batches.count) 批数据（\(batch.count) 条记录）")
        
        addTestRecords(batch, retryCount: 3) { success in
            if success {
                // 增加延迟到20秒
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    self.processBatch(index + 1, batches: batches)
                }
            } else {
                print("❌ 批次处理失败，停止后续处理")
            }
        }
    }
    
    private func deleteAllRecords(completion: @escaping (Bool) -> Void) {
        print("🗑️ 开始删除现有数据...")
        
        let db = Firestore.firestore()
        let recordsRef = db.collection("users")
            .document(userId)
            .collection("weightRecords")
        
        recordsRef.getDocuments { snapshot, error in
            if let error = error {
                print("❌ 获取记录失败: \(error)")
                DispatchQueue.main.async {
                    self.showError("删除失败")
                    completion(false)
                }
                return
            }
            
            guard let documents = snapshot?.documents, !documents.isEmpty else {
                print("✅ 没有现有数据需要删除")
                completion(true)
                return
            }
            
            print("📊 找到 \(documents.count) 条需要删除的记录")
            
            let batch = db.batch()
            documents.forEach { doc in
                print("🗑️ 准备删除记录: \(doc.documentID)")
                batch.deleteDocument(recordsRef.document(doc.documentID))
            }
            
            print("⏳ 开始执行批量删除...")
            batch.commit { error in
                if let error = error {
                    print("❌ 删除所有记录失败: \(error)")
                    DispatchQueue.main.async {
                        self.showError("删除失败")
                        completion(false)
                    }
                    return
                }
                
                // 清空用户文档中的历史记录
                db.collection("users").document(self.userId).updateData([
                    "weightHistory": [] as [Any],
                    "lastWeight": NSNull(),
                    "lastWeightDate": NSNull(),
                    "updatedAt": FieldValue.serverTimestamp()
                ] as [String: Any]) { error in
                    if let error = error {
                        print("❌ 清空历史记录失败: \(error)")
                        completion(false)
                        return
                    }
                    
                    print("✅ 成功删除所有记录和历史记录")
                    DispatchQueue.main.async {
                        self.weightRecords = []
                        self.saveToCacheStorage([])
                        completion(true)
                    }
                }
            }
        }
    }
    
    private func saveToCacheStorage(_ records: [WeightRecord]) {
        print("\n💾 保存数据到本地缓存:")
        print("  - 记录数量: \(records.count)")
        
        if let encoded = try? JSONEncoder().encode(records) {
            cachedWeightRecordsData = encoded
            print("✅ 数据成功保存到缓存")
            print("  - 缓存大小: \(ByteCountFormatter.string(fromByteCount: Int64(encoded.count), countStyle: .file))")
        } else {
            print("❌ 数据编码失败，无法保存到缓存")
        }
    }
    
    private func loadFromCacheStorage() -> [WeightRecord] {
        isLoading = true  // 开始加载时显示骨架屏
        
        if let records = try? JSONDecoder().decode([WeightRecord].self, from: cachedWeightRecordsData) {
            DispatchQueue.main.async {
                self.isLoading = false  // 加载完成后关闭骨架屏
            }
            return records
        }
        
        DispatchQueue.main.async {
            self.isLoading = false
        }
        return []
    }
    
    private func getDateInterval(for period: TimePeriod) -> Calendar.Component {
        switch period {
        case .week:
            return .day
        case .month, .threeMonths:
            return .weekOfMonth
        case .year, .all:
            return .month
        }
    }
    
    private func getDateFormat(for period: TimePeriod) -> Date.FormatStyle {
        switch period {
        case .week:
            return .dateTime.day().month() // 显示"月-日"
        case .month, .threeMonths:
            return .dateTime.day().month() // 显示"月-日"
        case .year, .all:
            return .dateTime.month().year() // 显示"年-月"
        }
    }
    
    private func getChartWidth(for period: TimePeriod, recordCount: Int) -> CGFloat {
        let baseWidth = UIScreen.main.bounds.width - 40
        let minWidthPerPoint: CGFloat
        
        switch period {
        case .week:
            minWidthPerPoint = 50 // 每个数据点至少50点宽度
        case .month:
            minWidthPerPoint = 30 // 每个数据点至少30点宽度
        case .threeMonths:
            minWidthPerPoint = 20 // 每个数据点至少20点宽度
        case .year, .all:
            minWidthPerPoint = 15 // 每个数据点至少15点宽度
        }
        
        return max(baseWidth, CGFloat(recordCount) * minWidthPerPoint)
    }
    
    private func getAxisValues(for period: TimePeriod) -> [Date] {
        let calendar = Calendar.current
        let now = Date()
        let startDate = getDateRange(for: chartPeriod).lowerBound
        var dates: [Date] = []
        var currentDate = startDate
        
        let step: Int
        let component: Calendar.Component
        
        switch period {
        case .week:
            step = 1
            component = .day
        case .month:
            step = 7
            component = .day
        case .threeMonths:
            step = 14
            component = .day
        case .year, .all:
            step = 1
            component = .month
        }
        
        while currentDate <= now {
            dates.append(currentDate)
            if let nextDate = calendar.date(byAdding: component, value: step, to: currentDate) {
                currentDate = nextDate
            } else {
                break
            }
        }
        
        // 确保包含最后一个日期
        if !dates.contains(where: { calendar.isDate($0, inSameDayAs: now) }) {
            dates.append(now)
        }
        
        return dates
    }
    
    private func syncLocalToHistory() {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)
        
        // 将本地缓存的记录转换为历史记录格式
        let historyRecords = weightRecords.map { record -> [String: Any] in
            return [
                "weight": record.weight,
                "date": Timestamp(date: record.date),
                "recordId": record.id
            ]
        }
        
        // 更新用户文档
        userRef.updateData([
            "weightHistory": historyRecords,
            "lastWeight": weightRecords.first?.weight ?? 0,
            "lastWeightDate": weightRecords.first.map { Timestamp(date: $0.date) } ?? FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ] as [String: Any]) { error in
            if let error = error {
                print("❌ 同步到历史记录失败: \(error)")
                return
            }
            print("✅ 成功同步 \(historyRecords.count) 条记录到历史记录")
        }
    }
    
    private func shouldReload() -> Bool {
        guard let last = lastLoadTime else { return true }
        return Date().timeIntervalSince(last) > 300 // 5分钟间隔
    }
    
    private func batchUpdate() {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // 收集更新
        var updates: [(ref: DocumentReference, data: [String: Any])] = []
        
        // 用户文档更新
        let userRef = db.collection("users").document(userId)
        if let latestRecord = weightRecords.first {
            updates.append((
                ref: userRef,
                data: [
                    "lastWeight": latestRecord.weight,
                    "lastWeightDate": Timestamp(date: latestRecord.date),
                    "updatedAt": FieldValue.serverTimestamp()
                ]
            ))
        }
        
        // 执行批量更新
        for update in updates {
            batch.updateData(update.data as [String: Any], forDocument: update.ref)
        }
        
        // 提交批量更新
        batch.commit { error in
            if let error = error {
                print("❌ 批量更新失败: \(error)")
                return
            }
            print("✅ 批量更新成功")
        }
    }
    
    private func retryOperation(operation: @escaping () -> Void, maxRetries: Int = 3) {
        var retries = 0
        func attempt() {
            guard retries < maxRetries else { return }
            operation()
            retries += 1
        }
        attempt()
    }
    
    private func checkDailyWeightLimit() -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let todayRecords = weightRecords.filter {
            calendar.isDate($0.date, inSameDayAs: today)
        }
        
        return todayRecords.count < maxDailyWeightRecords
    }
    
    private func checkDailyHeightLimit() -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // 使用 UserDefaults 存储最后更新身高的时间
        let lastHeightUpdate = UserDefaults.standard.object(forKey: "lastHeightUpdateDate") as? Date ?? .distantPast
        
        return !calendar.isDate(lastHeightUpdate, inSameDayAs: today)
    }
    
    // 使用 @State 和计算属性优化
    private var chartData: [WeightRecord] {
        let records = getFilteredRecords(for: chartPeriod)
        return processChartData(records)
    }
    
    @State private var lastChartUpdate = Date()
    @State private var chartUpdateThrottle = Debouncer(delay: 0.5)
    
    private func updateChartData() {
        chartUpdateThrottle.debounce {
            // 只有当数据真正变化时才更新
            let newData = getFilteredRecords(for: chartPeriod)
            if newData != weightRecords {
                DispatchQueue.main.async {
                    self.lastChartUpdate = Date()
                }
            }
        }
    }
    
    // 添加生成测试数据的函数
    private func generateLocalTestData() {
        print("📝 生成本地测试数据...")
        isTestMode = true  // 进入测试模式
        
        let calendar = Calendar.current
        let allTestRecords = (0..<12).map { i -> WeightRecord in
            let date = calendar.date(byAdding: .day, value: -(i * 3), to: Date()) ?? Date()
            let weight = 85.0 + Double.random(in: -0.5...0.5)
            
            return WeightRecord(
                id: UUID().uuidString,
                userId: userId,
                weight: round(weight * 10) / 10,
                date: date
            )
        }.sorted { $0.date > $1.date }
        
        DispatchQueue.main.async {
            self.weightRecords = Array(allTestRecords.prefix(self.pageSize))
            UserDefaults.standard.set(try? JSONEncoder().encode(allTestRecords), 
                                    forKey: "testWeightRecords")
            self.hasMoreRecords = allTestRecords.count > self.pageSize
            print("✅ 生成了 \(allTestRecords.count) 条测试记录，显示前 \(self.pageSize) 条")
        }
    }
    
    // 添加清除测试数据的函数
    private func clearLocalTestData() {
        DispatchQueue.main.async {
            self.weightRecords = []
            UserDefaults.standard.removeObject(forKey: "testWeightRecords")
            self.hasMoreRecords = false
            self.isTestMode = false  // 退出测试模式
            print("🗑️ 清除了所有测试记录")
        }
    }
    
    // 添加重置分页状态的函数
    private func resetPagination() {
        if isTestMode {
            if let data = UserDefaults.standard.data(forKey: "testWeightRecords"),
               let allRecords = try? JSONDecoder().decode([WeightRecord].self, from: data) {
                weightRecords = Array(allRecords.prefix(pageSize))
                hasMoreRecords = allRecords.count > pageSize
                print("📊 重置分页 - 测试模式:")
                print("  - 总记录数: \(allRecords.count)")
                print("  - 显示记录数: \(weightRecords.count)")
                print("  - 是否还有更多: \(hasMoreRecords)")
            }
        } else {
            // 实际数据的分页重置
            loadWeightRecords()
            print("📊 重置分页 - 实际数据模式")
        }
    }
    
    private func resetViewState() {
        withAnimation {
            isHistoryExpanded = false  // 折叠历史记录
            resetPagination()  // 重置分页
            isLoadingMore = false  // 重置加载状态
        }
    }
    
    // 添加刷新处理函数
    private func handleRefresh() async {
        isRefreshing = true
        
        // 检查网络连接
        let hasConnection = await checkDatabaseConnection()
        
        if hasConnection {
            // 有网络，同步数据
            print("\n📱 开始在线同步流程")
            syncWeightRecords()
            updateLastSyncTime()
            showSyncSuccess()
            
            // 重置分页状态
            DispatchQueue.main.async {
                print("\n🔄 重置分页状态:")
                print("  - 同步前记录数: \(self.weightRecords.count)")
                self.hasMoreRecords = false
                self.isLoadingMore = false
                resetPagination()
                print("  - 同步后记录数: \(self.weightRecords.count)")
                print("  - 是否还有更多: \(self.hasMoreRecords)")
                print("  - 分页大小: \(self.pageSize)")
            }
        } else {
            // 无网络，优化本地缓存加载
            DispatchQueue.main.async {
                // 加载本地缓存
                let cachedRecords = loadFromCacheStorage()
                if !cachedRecords.isEmpty {
                    self.weightRecords = cachedRecords
                    self.hasMoreRecords = cachedRecords.count > self.pageSize
                    print("📱 使用本地缓存: \(cachedRecords.count) 条记录")
                }
                
                // 显示离线提示
                showOfflineAlert()
                updateLastSyncTime()
            }
        }
        
        isRefreshing = false
    }
    
    // 更新同步时间显示
    private func updateLastSyncTime() {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        
        // 如果从未同步过（lastSyncDate 是 .distantPast）
        if lastSyncDate == .distantPast {
            lastSyncTimeString = "未同步，下拉刷新"
        } else {
            lastSyncTimeString = "上次同步: " + formatter.localizedString(for: lastSyncDate, relativeTo: Date())
        }
    }
    
    // 显示同步成功提示
    private func showSyncSuccess() {
        syncResultMessage = "数据同步成功"
        showSyncResult = true
        
        // 3秒后自动隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showSyncResult = false
        }
    }
    
    // 显示离线提示
    private func showOfflineAlert() {
        syncResultMessage = "网络连接失败，使用本地数据"
        showSyncResult = true
        
        // 3秒后自动隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showSyncResult = false
        }
    }
    
    // 添加检查数据库连接状态的函数
    private func checkDatabaseConnection() async -> Bool {
        do {
            print("⚡️ 正在检查数据库连接...")
            let db = Firestore.firestore()
            let _ = try await db.collection("users").document("test").getDocument(source: .server)
            print("✅ 数据库连接成功")
            return true
        } catch {
            print("❌ 数据库连接失败: \(error)")
            print("📱 尝试使用离线模式")
            return false
        }
    }
    
    // 添加预估天数计算函数
    private func calculateEstimatedDays(currentWeight: Double, goalWeight: Double, weightRecords: [WeightRecord]) -> Int? {
        guard weightRecords.count >= 2 else { return nil }
        
        // 计算每日平均变化率
        let dailyChanges = calculateDailyWeightChanges(records: weightRecords)
        guard !dailyChanges.isEmpty else { return nil }
        
        let averageChange = abs(dailyChanges.reduce(0, +) / Double(dailyChanges.count))
        let remainingDifference = abs(goalWeight - currentWeight)
        
        // 如果变化率太小，返回nil
        if averageChange < 0.01 { return nil }
        
        // 计算预估天数
        let estimatedDays = Int(ceil(remainingDifference / averageChange))
        return estimatedDays
    }
    
    // 计算每日体重变化
    private func calculateDailyWeightChanges(records: [WeightRecord]) -> [Double] {
        var changes: [Double] = []
        for i in 0..<records.count-1 {
            let change = abs(records[i].weight - records[i+1].weight)
            let days = Calendar.current.dateComponents([.day], from: records[i+1].date, to: records[i].date).day ?? 1
            let dailyChange = change / Double(max(days, 1))
            changes.append(dailyChange)
        }
        return changes
    }
    
    // 修改喝水卡片组件
    private var waterIntakeCard: some View {
        VStack(spacing: 15) {
            // 标题和进度
            HStack {
                Text("今日饮水")
                    .font(.headline)
                Spacer()
                Text("\(waterIntakeToday)/\(dailyWaterGoal) 杯")
                    .foregroundColor(.blue)
            }
            
            // 水杯进度指示器
            HStack(spacing: 12) {
                ForEach(0..<dailyWaterGoal, id: \.self) { index in
                    WaterCupView(
                        isFilled: index < waterIntakeToday,
                        isAnimating: index == waterIntakeToday - 1 && showWaterAnimation
                    )
                }
            }
            .padding(.vertical, 8)
            
            // 添加水量按钮
            Button(action: {
                withAnimation(.spring()) {
                    if waterIntakeToday < dailyWaterGoal {
                        showWaterAnimation = true
                        waterIntakeToday += 1
                        // 更新记录
                        updateWaterIntake()
                        
                        // 检查是否完成每日目标
                        if waterIntakeToday == dailyWaterGoal {
                            // 触发完成动画
                            showCompletionAnimation = true
                            // 3秒后关闭完成动画
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                showCompletionAnimation = false
                            }
                        }
                        
                        // 3秒后关闭水杯动画
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            showWaterAnimation = false
                        }
                    }
                }
            }) {
                Label(waterIntakeToday >= dailyWaterGoal ? "你已经喝够了！" : "喝一杯水", 
                      systemImage: waterIntakeToday >= dailyWaterGoal ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.footnote)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(waterIntakeToday < dailyWaterGoal ? Color.blue : Color.green)  // 完成后变成绿色
                    .cornerRadius(20)
            }
            .disabled(waterIntakeToday >= dailyWaterGoal)
            .overlay(
                Group {
                    if showCompletionAnimation {
                        CompletionAnimationView()
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
    
    // 水杯视图组件
    private struct WaterCupView: View {
        let isFilled: Bool
        let isAnimating: Bool
        
        var body: some View {
            Image(systemName: "cup.and.saucer")
                .font(.title2)
                .foregroundColor(isFilled ? .blue : .gray.opacity(0.3))
                .scaleEffect(isAnimating ? 1.5 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
                .overlay(
                    Circle()
                        .stroke(Color.blue.opacity(isAnimating ? 0.5 : 0), lineWidth: 2)
                        .scaleEffect(isAnimating ? 2 : 1)
                        .opacity(isAnimating ? 0 : 1)
                        .animation(.easeOut(duration: 1), value: isAnimating)
                )
        }
    }
    
    // 修改每日重置检查函数
    private func checkAndResetWaterIntake() {
        let calendar = Calendar.current
        let now = Date()
        let lastResetDate = UserDefaults.standard.object(forKey: "lastWaterResetDate") as? Date ?? .distantPast
        
        // 如果不是同一天，直接重置，不检查昨天的记录
        if !calendar.isDate(lastResetDate, inSameDayAs: now) {
            waterIntakeToday = 0
            UserDefaults.standard.set(now, forKey: "lastWaterResetDate")
            updateWaterIntake()
            print("🔄 重置每日喝水记录")
        }
        
        // 设置当天23:59的检查
        scheduleEndOfDayCheck()
    }
    
    // 添加当天结束时的检查函数
    private func scheduleEndOfDayCheck() {
        let calendar = Calendar.current
        let now = Date()
        
        // 获取今天23:59的时间
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now) else {
            return
        }
        
        // 如果已经过了今天的23:59，就不需要设置通知
        guard endOfDay > now else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "今日喝水总结"
        content.body = waterIntakeToday < dailyWaterGoal ? 
            "今日只喝了 \(waterIntakeToday)/\(dailyWaterGoal) 杯水，记得保持规律饮水习惯哦！" :
            "恭喜完成今日喝水目标！"
        content.sound = .default
        
        // 创建日期组件
        let triggerDate = calendar.dateComponents([.hour, .minute], from: endOfDay)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        // 创建通知请求
        let request = UNNotificationRequest(
            identifier: "endOfDayWaterCheck",
            content: content,
            trigger: trigger
        )
        
        // 添加通知
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 设置每日总结通知失败: \(error)")
            } else {
                print("✅ 已设置今日喝水总结通知")
            }
        }
    }
    
    // 添加未完成通知函数
    private func sendIncompleteNotification(cups: Int) {
        let content = UNMutableNotificationContent()
        content.title = "未完成今日喝水目标"
        content.body = "今日只喝了 \(cups)/\(dailyWaterGoal) 杯水，记得保持规律饮水习惯哦！"
        content.sound = .default
        
        // 创建通知请求
        let request = UNNotificationRequest(
            identifier: "waterIncomplete",
            content: content,
            trigger: nil  // 立即发送
        )
        
        // 发送通知
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 发送未完成通知失败: \(error)")
            } else {
                print("✅ 已发送未完成通知")
            }
        }
    }
    
    // 添加喝水记录管理函数
    private func updateWaterIntake() {
        print("\n========== 开始更新喝水记录 ==========")
        print("📊 当前状态:")
        print("  - 已喝水杯数: \(waterIntakeToday)")
        print("  - 目标杯数: \(dailyWaterGoal)")
        print("  - 上次同步时间: \(lastWaterSync)")

        let db = Firestore.firestore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        print("📝 准备更新数据库...")
        print("  - 文档路径: users/\(userId)/waterIntake/\(today.ISO8601Format())")
        
        // 使用批量写入减少数据库访问
        let batch = db.batch()
        
        // 1. 更新用户文档
        let userRef = db.collection("users").document(userId)
        batch.updateData([
            "hasWaterIntakeEnabled": true,
            "lastWaterIntakeUpdate": Date()
        ], forDocument: userRef)
        print("✓ 已准备用户文档更新")
        
        // 2. 添加/更新今日喝水记录
        let waterRef = db.collection("users")
            .document(userId)
            .collection("waterIntake")
            .document(today.ISO8601Format())
        
        let data: [String: Any] = [
            "date": today,
            "cups": waterIntakeToday,
            "lastUpdated": Date()
        ]
        batch.setData(data, forDocument: waterRef, merge: true)
        print("✓ 已准备喝水记录更新")
        
        // 3. 执行批量写入
        batch.commit { error in
            if let error = error {
                print("❌ 喝水记录同步失败:")
                print("  - 错误: \(error.localizedDescription)")
            } else {
                print("✅ 喝水记录同步成功:")
                print("  - 杯数: \(self.waterIntakeToday)")
                print("  - 时间: \(Date())")
                
                DispatchQueue.main.async {
                    self.lastWaterSync = Date()
                    
                    // 保存到本地缓存
                    let record = WaterIntakeRecord(
                        date: today,
                        cups: self.waterIntakeToday,
                        lastUpdated: Date()
                    )
                    if let encoded = try? JSONEncoder().encode(record) {
                        UserDefaults.standard.set(encoded, forKey: "todayWaterIntake")
                        print("✅ 已更新本地缓存")
                    }
                }
            }
        }
        
        // 重新调度通知
        scheduleWaterReminders()
    }
    
    // 加载今日喝水记录
    private func loadTodayWaterIntake() {
        print("\n📱 开始加载今日喝水记录...")
        waterIntakeManager.startListening(userId: userId) { cups in
            DispatchQueue.main.async {
                self.waterIntakeToday = cups
            }
        }
    }
    
    // 请求通知权限
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        
        // 先检查当前权限状态
        center.getNotificationSettings { settings in
            print("📱 当前通知权限状态: \(settings.authorizationStatus.rawValue)")
            
            switch settings.authorizationStatus {
            case .notDetermined:
                // 请求权限
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        print("❌ 通知权限请求失败: \(error)")
                        return
                    }
                    
                    if granted {
                        print("✅ 通知权限已授予")
                        DispatchQueue.main.async {
                            self.waterNotificationsEnabled = true
                            self.scheduleWaterReminders()
                            
                            // 立即发送一条测试通知
                            self.sendTestNotification()
                        }
                    } else {
                        print("⚠️ 通知权限被拒绝")
                    }
                }
            case .denied:
                print("⚠️ 通知权限已被拒绝，请在设置中开启")
                // 提示用户去设置中开启通知
                DispatchQueue.main.async {
                    self.showNotificationSettingsAlert()
                }
            case .authorized:
                print("✅ 已有通知权限")
                DispatchQueue.main.async {
                    self.waterNotificationsEnabled = true
                    self.scheduleWaterReminders()
                }
            default:
                break
            }
        }
    }
    
    // 添加测试通知函数
    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "通知测试"
        content.body = "如果您看到这条消息，说明通知已经设置成功！"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "testNotification",
            content: content,
            trigger: nil  // 立即发送
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 测试通知发送失败: \(error)")
            } else {
                print("✅ 测试通知发送成功")
            }
        }
    }
    
    // 添加提示用户开启通知的弹窗
    private func showNotificationSettingsAlert() {
        let alert = UIAlertController(
            title: "需要通知权限",
            message: "请在设置中开启通知，以便接收喝水提醒",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        // 获取当前的 UIWindow 场景
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let viewController = windowScene.windows.first?.rootViewController {
            viewController.present(alert, animated: true)
        }
    }
    
    // 修改通知设置函数
    private func scheduleWaterReminders() {
        // 如果已经完成今日目标，取消所有提醒
        if waterIntakeToday >= dailyWaterGoal {
            cancelWaterReminders()
            return
        }
        
        let center = UNUserNotificationCenter.current()
        
        // 先清除现有的提醒
        center.removeAllPendingNotificationRequests()
        
        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = "喝水提醒"
        content.categoryIdentifier = "water_reminder"
        
        // 使用表情符号创建进度条效果
        let filledDrops = String(repeating: "💧", count: waterIntakeToday)
        let emptyDrops = String(repeating: "⚪️", count: dailyWaterGoal - waterIntakeToday)
        let progressBar = filledDrops + emptyDrops
        
        content.body = """
        已经两小时没有喝水了
        今日进度：
        \(progressBar)
        \(waterIntakeToday)/\(dailyWaterGoal) 杯
        """
        
        content.sound = .default
        content.badge = NSNumber(value: waterIntakeToday + 1)
        
        // 添加通知动作
        let drinkAction = UNNotificationAction(
            identifier: "DRINK_ACTION",
            title: "已喝一杯",
            options: .foreground
        )
        
        let category = UNNotificationCategory(
            identifier: "water_reminder",
            actions: [drinkAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // 注册通知类别
        center.setNotificationCategories([category])
        
        // 创建触发器，每2小时重复一次
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: notificationInterval,
            repeats: true
        )
        
        // 创建通知请求
        let request = UNNotificationRequest(
            identifier: "waterReminder",
            content: content,
            trigger: trigger
        )
        
        // 添加通知请求
        center.add(request) { error in
            if let error = error {
                print("❌ 添加通知失败: \(error)")
            } else {
                print("✅ 喝水提醒已设置")
            }
        }
    }
    
    // 取消所有喝水提醒
    private func cancelWaterReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("🔕 已取消所有喝水提醒")
    }
    
    // 添加测试通知函数
    private func testNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("📱 当前通知权限状态: \(settings.authorizationStatus.rawValue)")
            
            guard settings.authorizationStatus == .authorized else {
                print("⚠️ 通知未授权，请在设置中开启通知权限")
                DispatchQueue.main.async {
                    self.showNotificationSettingsAlert()
                }
                return
            }
            
            // 发送三种不同场景的通知
            let filledDrops = String(repeating: "💧", count: waterIntakeToday)
            let emptyDrops = String(repeating: "⚪️", count: dailyWaterGoal - waterIntakeToday)
            let progressBar = filledDrops + emptyDrops
            
            let notifications = [
                (title: "喝水提醒", 
                 body: """
                 已经两小时没有喝水了
                 今日进度：
                 \(progressBar)
                 \(waterIntakeToday)/\(dailyWaterGoal) 杯
                 """, 
                 delay: 0),
                (title: "完成目标提醒", 
                 body: "太棒了！你已经完成今日喝水目标！继续保持哦！", 
                 delay: 5),
                (title: "每日总结", 
                 body: "今日喝水进度：\(waterIntakeToday)/\(dailyWaterGoal)，记得保持规律饮水习惯！", 
                 delay: 10)
            ]
            
            for (index, notification) in notifications.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = notification.title
                content.body = notification.body
                content.sound = .default
                content.badge = NSNumber(value: index + 1)
                
                // 创建触发器
                let trigger = notification.delay > 0 ? 
                    UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(notification.delay), repeats: false) : nil
                
                // 创建请求
                let request = UNNotificationRequest(
                    identifier: "test_notification_\(index)",
                    content: content,
                    trigger: trigger
                )
                
                // 添加通知请求
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ 通知 #\(index) 发送失败: \(error.localizedDescription)")
                    } else {
                        print("✅ 通知 #\(index) 已计划发送 (延迟: \(notification.delay)秒)")
                    }
                }
            }
        }
    }
    
    // 在 WeightView 中添加体重记录提醒的设置
    private func scheduleWeightReminders() {
        let center = UNUserNotificationCenter.current()
        
        // 先清除现有的体重记录提醒
        center.removePendingNotificationRequests(withIdentifiers: [
            "morningWeightReminder",
            "afternoonWeightReminder", 
            "eveningWeightReminder",
            "endOfDayWeightCheck"
        ])
        
        // 设置提醒时间
        let reminders = [
            (hour: 8, minute: 0, identifier: "morningWeightReminder", title: "早间体重记录提醒", body: "早上好！记得记录今天的体重哦"),
            (hour: 16, minute: 0, identifier: "afternoonWeightReminder", title: "下午体重记录提醒", body: "下午好！别忘了记录今天的体重"),
            (hour: 23, minute: 0, identifier: "eveningWeightReminder", title: "晚间体重记录提醒", body: "今天还没有记录体重，现在记录一下吧"),
            (hour: 23, minute: 59, identifier: "endOfDayWeightCheck", title: "每日体重记录提醒", body: "今天还没有记录体重，记得保持每日记录习惯哦")
        ]
        
        let calendar = Calendar.current
        
        for reminder in reminders {
            var dateComponents = DateComponents()
            dateComponents.hour = reminder.hour
            dateComponents.minute = reminder.minute
            
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: true
            )
            
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: trigger
            )
            
            center.add(request) { error in
                if let error = error {
                    print("❌ 设置体重提醒失败: \(error)")
                } else {
                    print("✅ 已设置体重提醒: \(reminder.identifier)")
                }
            }
        }
    }
    
    // 添加体重通知测试函数
    private func testWeightNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("📱 当前通知权限状态: \(settings.authorizationStatus.rawValue)")
            
            guard settings.authorizationStatus == .authorized else {
                print("⚠️ 通知未授权，请在设置中开启通知权限")
                DispatchQueue.main.async {
                    self.showNotificationSettingsAlert()
                }
                return
            }
            
            // 发送三种不同场景的通知
            let notifications = [
                (title: "早间体重记录提醒", 
                 body: "早上好！记得记录今天的体重哦", 
                 delay: 0),
                (title: "下午体重记录提醒", 
                 body: "下午好！别忘了记录今天的体重", 
                 delay: 5),
                (title: "每日体重记录提醒", 
                 body: "今天还没有记录体重，记得保持每日记录习惯哦", 
                 delay: 10)
            ]
            
            for (index, notification) in notifications.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = notification.title
                content.body = notification.body
                content.sound = .default
                content.badge = NSNumber(value: index + 1)
                
                // 创建触发器
                let trigger = notification.delay > 0 ? 
                    UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(notification.delay), repeats: false) : nil
                
                // 创建请求
                let request = UNNotificationRequest(
                    identifier: "test_weight_notification_\(index)",
                    content: content,
                    trigger: trigger
                )
                
                // 添加通知请求
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ 体重通知 #\(index) 发送失败: \(error.localizedDescription)")
                    } else {
                        print("✅ 体重通知 #\(index) 已计划发送 (延迟: \(notification.delay)秒)")
                    }
                }
            }
        }
    }
    
    // 在 WeightView 中添加体重变化监控函数
    private func checkWeightChange() {
        let calendar = Calendar.current
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        
        // 获取最近三天的记录
        let recentRecords = weightRecords.filter { record in
            record.date >= threeDaysAgo
        }.sorted { $0.date > $1.date }
        
        // 如果有足够的记录进行比较
        if let latestWeight = recentRecords.first?.weight,
           let oldestWeight = recentRecords.last?.weight {
            let weightChange = oldestWeight - latestWeight
            
            // 如果三天内体重下降超过5kg
            if weightChange > 5.0 {
                // 发送健康提醒通知
                let content = UNMutableNotificationContent()
                content.title = "健康提醒"
                content.body = """
                    您在最近三天内体重下降了 \(String(format: "%.1f", weightChange))kg
                    体重下降过快可能影响健康，请注意：
                    · 保持均衡饮食
                    · 适量运动
                    · 充足睡眠
                    如有疑虑请咨询医生
                    """
                content.sound = .default
                
                // 立即发送通知
                let request = UNNotificationRequest(
                    identifier: "weightChangeWarning",
                    content: content,
                    trigger: nil
                )
                
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ 发送体重变化警告失败: \(error)")
                    } else {
                        print("✅ 已发送体重变化警告")
                        print("  - 变化幅度: \(weightChange)kg")
                        print("  - 起始体重: \(oldestWeight)kg")
                        print("  - 当前体重: \(latestWeight)kg")
                    }
                }
            }
        }
    }
    
    private var offlineTestSheet: some View {
        NavigationView {
            List {
                // 1. 离线添加记录测试
                Section(header: Text("离线添加测试")) {
                    Button("添加离线记录") {
                        let weight = Double.random(in: 50...80)
                        addWeightRecord(weight)
                    }
                }
                
                // 2. 查看离线队列
                Section(header: Text("离线队列状态")) {
                    let operations = offlineManager.getPendingOperations()
                    if !operations.isEmpty {
                        ForEach(operations) { operation in
                            VStack(alignment: .leading) {
                                Text("类型: \(operation.type.rawValue)")
                                Text("时间: \(operation.timestamp.formatted())")
                                Text("重试次数: \(operation.retryCount)")
                            }
                        }
                    } else {
                        Text("队列为空")
                    }
                }
                
                // 3. 网络状态测试
                Section(header: Text("网络状态")) {
                    Toggle("模拟离线", isOn: $isOfflineMode)
                        .onChange(of: isOfflineMode) { oldValue, newValue in
                            // 这里可以模拟网络状态变化
                            if newValue {
                                print("📱 已切换到离线模式")
                            } else {
                                print("📱 已恢复在线模式")
                                // 尝试同步离线数据
                                syncWeightRecords()
                            }
                        }
                }
                
                // 4. 手动操作
                Section(header: Text("手动操作")) {
                    Button("立即同步") {
                        syncWeightRecords()
                    }
                    
                    Button("清除离线队列", role: .destructive) {
                        offlineManager.clearProcessedOperations()
                    }
                }
                
                // 在离线测试面板中添加同步状态监控
                Section(header: Text("同步状态")) {
                    VStack(alignment: .leading) {
                        Text("待同步操作: \(offlineManager.pendingOperationsCount)")
                        Text("上次同步: \(lastSyncDate.formatted())")
                        Text("网络状态: \(isOffline ? "离线" : "在线")")
                    }
                }
            }
            .navigationTitle("离线功能测试")
            .navigationBarItems(trailing: Button("完成") {
                showOfflineTestSheet = false
            })
        }
    }
    
    // 在 WeightView 中添加
    private func addRecordToFirestore(_ record: WeightRecord) {
        print("🔄 开始添加体重记录: \(record.weight)kg")
        
        // 检查每日限制
        guard checkDailyWeightLimit() else {
            DispatchQueue.main.async {
                self.showError("今日记录已达上限(\(maxDailyWeightRecords)次)")
                self.showingAddSheet = false
            }
            return
        }
        
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // 1. 创建体重记录
        let recordRef = db.collection("users")
            .document(userId)
            .collection("weightRecords")
            .document(record.id)
        
        let recordData: [String: Any] = [
            "weight": record.weight,
            "date": Timestamp(date: record.date),
            "userId": record.userId
        ]
        
        batch.setData(recordData, forDocument: recordRef)
        
        // 2. 更新用户文档，包括历史记录
        let userRef = db.collection("users").document(userId)
        let weightHistory: [String: Any] = [
            "weight": record.weight,
            "date": Timestamp(date: record.date),
            "recordId": record.id
        ]
        
        let userData: [String: Any] = [
            "lastWeight": record.weight,
            "lastWeightDate": Timestamp(date: record.date),
            "updatedAt": FieldValue.serverTimestamp(),
            "weightHistory": FieldValue.arrayUnion([weightHistory])
        ]
        
        batch.updateData(userData, forDocument: userRef)
        
        // 3. 执行批量写入
        batch.commit { error in
            if let error = error {
                print("❌ 保存体重失败: \(error)")
                DispatchQueue.main.async {
                    self.showError("保存体重失败")
                }
                return
            }
            
            print("✅ 体重记录保存成功: \(record.weight)kg")
            DispatchQueue.main.async {
                self.showingAddSheet = false
                self.newWeight = ""
                
                // 添加体重变化检查
                self.checkWeightChange()
            }
        }
    }

    // 在 WeightView 中添加
    private func processChartData(_ records: [WeightRecord]) -> [WeightRecord] {
        let calendar = Calendar.current
        
        // 根据时间段选择合适的数据聚合方式
        switch chartPeriod {
        case .week:
            // 每小时聚合
            return records.chunked(by: { calendar.isDate($0.date, equalTo: $1.date, toGranularity: .hour) })
                .map { chunk -> WeightRecord in
                    let averageWeight = chunk.map { $0.weight }.reduce(0, +) / Double(chunk.count)
                    return WeightRecord(
                        id: chunk[0].id,
                        userId: chunk[0].userId,
                        weight: averageWeight,
                        date: chunk[0].date
                    )
                }
            
        case .month, .threeMonths:
            // 每天聚合
            return records.chunked(by: { calendar.isDate($0.date, equalTo: $1.date, toGranularity: .day) })
                .map { chunk -> WeightRecord in
                    let averageWeight = chunk.map { $0.weight }.reduce(0, +) / Double(chunk.count)
                    return WeightRecord(
                        id: chunk[0].id,
                        userId: chunk[0].userId,
                        weight: averageWeight,
                        date: chunk[0].date
                    )
                }
            
        case .year, .all:
            // 每周聚合
            return records.chunked(by: { calendar.isDate($0.date, equalTo: $1.date, toGranularity: .weekOfYear) })
                .map { chunk -> WeightRecord in
                    let averageWeight = chunk.map { $0.weight }.reduce(0, +) / Double(chunk.count)
                    return WeightRecord(
                        id: chunk[0].id,
                        userId: chunk[0].userId,
                        weight: averageWeight,
                        date: chunk[0].date
                    )
                }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: Double
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(value, specifier: "%.1f") \(unit)")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct WeightRecord: Identifiable, Equatable, Codable {
    let id: String
    let userId: String
    let weight: Double
    let date: Date
    
    // 实现 Equatable 协议
    static func == (lhs: WeightRecord, rhs: WeightRecord) -> Bool {
        return lhs.id == rhs.id &&
               lhs.userId == rhs.userId &&
               lhs.weight == rhs.weight &&
               lhs.date == rhs.date
    }
}

// 添加 Debouncer 类
class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    
    init(delay: TimeInterval) {
        self.delay = delay
    }
    
    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        let newWorkItem = DispatchWorkItem(block: action)
        workItem = newWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: newWorkItem)
    }
    
    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

// 在 WeightView 外部添加骨架屏组件
struct SkeletonView: View {
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.2))
                    .offset(x: isAnimating ? 400 : -400)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
    }
}

// 添加骨架屏布局
struct WeightViewSkeleton: View {
    var body: some View {
        VStack(spacing: 20) {
            // BMI卡片骨架
            SkeletonView()
                .frame(height: 120)
            
            // 图表切换骨架
            SkeletonView()
                .frame(height: 40)
            
            // 图表骨架
            SkeletonView()
                .frame(height: 200)
            
            // 目标进度骨架
            SkeletonView()
                .frame(height: 100)
            
            // 记录列表骨架
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonView()
                        .frame(height: 60)
                }
            }
        }
        .padding()
    }
}

// 添加引导页面组件
struct EmptyStateView: View {
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "scale.3d")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding(.bottom, 10)
            
            Text("开始记录你的体重")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("记录体重可以帮助你更好地了解身体变化\n每天记录，保持健康")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: action) {
                Label("添加第一条记录", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)
        }
        .padding()
        .frame(maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// 添加完成动画视图
private struct CompletionAnimationView: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // 背景模糊效果
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 200, height: 200)
                .scaleEffect(scale)
                .opacity(opacity * 0.3)
            
            // 庆祝图标
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .opacity(opacity)
            
            // 星星效果
            ForEach(0..<8) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.yellow)
                    .offset(x: 60 * cos(Double(index) * .pi / 4), 
                           y: 60 * sin(Double(index) * .pi / 4))
                    .rotationEffect(.degrees(rotation))
                    .scaleEffect(scale)
                    .opacity(opacity)
            }
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

// 在文件最开始添加，在 import 语句之后
extension Array {
    func chunked(by belongInSameChunk: (Element, Element) -> Bool) -> [[Element]] {
        guard !isEmpty else { return [] }
        var result: [[Element]] = [[self[0]]]
        for element in self.dropFirst() {
            if belongInSameChunk(result.last!.last!, element) {
                result[result.count - 1].append(element)
            } else {
                result.append([element])
            }
        }
        return result
    }
}

// 新增一个管理类来处理监听器
class WaterIntakeManager: ObservableObject {
    private var waterIntakeListener: ListenerRegistration?
    
    func startListening(userId: String, completion: @escaping (Int) -> Void) {
        print("\n========== 开始监听喝水记录 ==========")
        print("📱 用户ID: \(userId)")
        
        // 先清理现有监听器
        cleanup()
        
        // 确保 userId 不为空
        guard !userId.isEmpty else {
            print("❌ 错误: 用户ID为空")
            print("ℹ️ 跳过监听器设置")
            completion(0) // 返回默认值
            return
        }
        
        let db = Firestore.firestore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let docId = today.ISO8601Format()
        
        print("📄 文档路径: users/\(userId)/waterIntake/\(docId)")
        
        waterIntakeListener = db.collection("users")
            .document(userId)
            .collection("waterIntake")
            .document(docId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil else {
                    print("❌ 错误: self 已被释放")
                    return
                }
                
                if let error = error {
                    print("❌ 监听失败:")
                    print("  - 错误类型: \(error.localizedDescription)")
                    print("  - 错误详情: \(error)")
                    return
                }
                
                if let data = snapshot?.data() {
                    print("📥 收到数据更新:")
                    print("  - 数据: \(data)")
                    
                    if let cups = data["cups"] as? Int {
                        print("✅ 解析成功:")
                        print("  - 杯数: \(cups)")
                        
                        completion(cups)
                        
                        // 保存到本地缓存
                        let record = WaterIntakeRecord(
                            date: today,
                            cups: cups,
                            lastUpdated: Date()
                        )
                        if let encoded = try? JSONEncoder().encode(record) {
                            UserDefaults.standard.set(encoded, forKey: "todayWaterIntake")
                            print("✅ 已更新本地缓存")
                        } else {
                            print("⚠️ 缓存编码失败")
                        }
                    } else {
                        print("⚠️ cups 字段解析失败")
                        print("  - 原始数据: \(data)")
                    }
                } else {
                    print("ℹ️ 未找到今日记录，使用默认值")
                    completion(0)
                }
            }
    }
    
    func cleanup() {
        print("\n========== 清理喝水记录监听器 ==========")
        if waterIntakeListener != nil {
            waterIntakeListener?.remove()
            waterIntakeListener = nil
            print("✅ 监听器已清理")
        } else {
            print("ℹ️ 没有活动的监听器需要清理")
        }
    }
    
    deinit {
        print("🗑️ WaterIntakeManager 被释放")
        cleanup()
    }
}

#Preview {
    WeightView()
}  