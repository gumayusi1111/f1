import SwiftUI
import FirebaseFirestore
import AVFoundation

struct CalendarView: View {
    @State private var selectedDate = Date()
    @State private var weekDates: [Date] = []
    @State private var trainingRecords: [String: [TrainingRecord]] = [:]
    @State private var restDays: [String] = []
    @State private var showingAddTraining = false
    @State private var showingTutorial = false
    
    @AppStorage("hasShownCalendarTutorial") private var hasShownCalendarTutorial: Bool = false
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("cachedRestDaysData") private var cachedRestDaysData: Data = Data()
    @AppStorage("lastCalendarSyncDate") private var lastCalendarSyncDate: Date = .distantPast
    
    let calendar = Calendar.current
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    @State private var currentSwipedDate: Date? = nil {
        didSet {
            print("📱 currentSwipedDate changed to: \(String(describing: currentSwipedDate))")
        }
    }
    
    @State private var isAnimating = false
    @State private var isHovered = false
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    @State private var trainingParts: [String: String] = [:]
    
    var body: some View {
        VStack(spacing: 16) {
            headerSection
            dateNavigationSection
            backToTodayButton
            calendarListSection
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingAddTraining) {
            DayTrainingView(date: selectedDate)
        }
        .onAppear {
            updateWeekDates()
            loadTrainingRecords()
            loadRestDays()
            loadTrainingParts()
            
            if !hasShownCalendarTutorial {
                showingTutorial = true
                hasShownCalendarTutorial = true
            }
        }
        .onDisappear {
            currentSwipedDate = nil
        }
        .alert("使用提示", isPresented: $showingTutorial) {
            Button("知道了") {
                showingTutorial = false
            }
        } message: {
            Text("向左滑动可以将某天设置为休息日。\n休息日将不会提醒您添加训练记录。")
        }
        .alert("加载失败", isPresented: $showError) {
            Button("重试") {
                loadTrainingRecords()
                loadRestDays()
            }
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        Text("训练日历")
            .font(.system(size: 28, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .foregroundStyle(
                LinearGradient(
                    colors: [.black, .gray.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
    }
    
    private var dateNavigationSection: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: previousWeek) {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "chevron.left")
                                .foregroundColor(.blue)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text(selectedDate.formatted(.dateTime.year()))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(selectedDate.formatted(.dateTime.month()))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(weekRangeText())
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: nextWeek) {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "chevron.right")
                                .foregroundColor(.blue)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal)
    }
    
    private var backToTodayButton: some View {
        let isCurrentWeek = calendar.isDate(Date(), equalTo: selectedDate, toGranularity: .weekOfYear)
        
        return Group {
            if !isCurrentWeek {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedDate = Date()
                        updateWeekDates()
                        loadTrainingRecords()
                        isAnimating = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14, weight: .medium))
                            .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        Text("回到今天")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                            .shadow(color: .blue.opacity(0.1),
                                    radius: isHovered ? 8 : 4,
                                    x: 0,
                                    y: isHovered ? 4 : 2)
                    )
                }
                .buttonStyle(HoverButtonStyle())
                .padding(.vertical, 4)
                .onAppear {
                    isAnimating = false
                }
            }
        }
    }
    
    private var calendarListSection: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 1) {
                ForEach(weekDates, id: \.self) { date in
                    DayCell(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        hasTraining: trainingRecords[dateFormatter.string(from: date)]?.isEmpty == false,
                        isToday: calendar.isDateInToday(date),
                        isRestDay: restDays.contains(dateFormatter.string(from: date)),
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = date
                                showingAddTraining = true
                            }
                        },
                        setRestDay: setRestDay,
                        calendar: calendar,
                        trainingRecords: trainingRecords,
                        dateFormatter: dateFormatter,
                        currentSwipedDate: $currentSwipedDate
                    )
                    Divider()
                        .opacity(0.5)
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
            .padding(.horizontal)
        }
        .scrollDisabled(true)
    }
    
    private func updateWeekDates() {
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
        weekDates = (0...6).map { day in
            calendar.date(byAdding: .day, value: day, to: startOfWeek)!
        }
    }
    
    private func nextWeek() {
        if let newDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) {
            selectedDate = newDate
            updateWeekDates()
            loadTrainingRecords()
        }
    }
    
    private func previousWeek() {
        if let newDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) {
            selectedDate = newDate
            updateWeekDates()
            loadTrainingRecords()
        }
    }
    
    private func loadTrainingRecords() {
        guard !userId.isEmpty else { return }
        
        let db = Firestore.firestore()
        
        // 获取当前周的开始和结束日期
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
        
        db.collection("users")
            .document(userId)
            .collection("trainings")
            .whereField("date", isGreaterThanOrEqualTo: startOfWeek)
            .whereField("date", isLessThan: endOfWeek)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error loading training records: \(error)")
                    return
                }
                
                var newRecords: [String: [TrainingRecord]] = [:]
                
                snapshot?.documents.forEach { document in
                    let data = document.data()
                    if let type = data["type"] as? String,
                       let bodyPart = data["bodyPart"] as? String,
                       let sets = data["sets"] as? Int,
                       let reps = data["reps"] as? Int,
                       let weight = data["weight"] as? Double,
                       let notes = data["notes"] as? String,
                       let date = (data["date"] as? Timestamp)?.dateValue() {
                        
                        let record = TrainingRecord(
                            id: document.documentID,
                            type: type,
                            bodyPart: bodyPart,
                            sets: sets,
                            reps: reps,
                            weight: weight,
                            notes: notes,
                            date: date
                        )
                        
                        let dateString = dateFormatter.string(from: date)
                        if newRecords[dateString] == nil {
                            newRecords[dateString] = []
                        }
                        newRecords[dateString]?.append(record)
                    }
                }
                
                self.trainingRecords = newRecords
            }
    }
    
    private func loadRestDays() {
        print("\n========== 开始加载休息日数据 ==========")
        print("⏰ 当前时间: \(Date())")
        print("📅 上次同步时间: \(lastCalendarSyncDate)")
        
        let shouldSyncData = shouldSync()
        print("🔍 检查是否需要同步:")
        print("  - 上次同步是否是今天: \(!shouldSyncData)")
        print("  - 需要同步: \(shouldSyncData)")
        
        if shouldSyncData {
            print("\n🔄 从数据库加载数据...")
            let db = Firestore.firestore()
            db.collection("users")
                .document(userId)
                .collection("calendar")
                .document("restDays")
                .getDocument { snapshot, error in
                    if let error = error {
                        print("❌ 数据库加载失败: \(error)")
                        print("📦 使用本地缓存作为备选")
                        self.restDays = self.loadFromCache()
                        return
                    }
                    
                    if let data = snapshot?.data(),
                       let days = data["days"] as? [String] {
                        print("✅ 数据库加载成功:")
                        print("  - 休息日数量: \(days.count)")
                        self.restDays = days
                        self.saveToCache(days)
                        self.lastCalendarSyncDate = Date()
                    }
                }
        } else {
            print("\n📦 使用本地缓存:")
            self.restDays = loadFromCache()
        }
    }
    
    private func saveToCache(_ days: [String]) {
        print("\n💾 保存数据到本地缓存:")
        print("  - 休息日数量: \(days.count)")
        
        if let encoded = try? JSONEncoder().encode(days) {
            cachedRestDaysData = encoded
            print("✅ 数据成功保存到缓存")
            print("  - 缓存大小: \(ByteCountFormatter.string(fromByteCount: Int64(encoded.count), countStyle: .file))")
        } else {
            print("❌ 数据编码失败，无法保存到缓存")
        }
    }
    
    private func loadFromCache() -> [String] {
        print("\n📂 从本地缓存加载数据:")
        print("  - 缓存大小: \(ByteCountFormatter.string(fromByteCount: Int64(cachedRestDaysData.count), countStyle: .file))")
        
        if let decoded = try? JSONDecoder().decode([String].self, from: cachedRestDaysData) {
            print("✅ 成功解码缓存数据")
            print("  - 休息日数量: \(decoded.count)")
            if !decoded.isEmpty {
                print("  - 休息日列表: \(decoded.joined(separator: ", "))")
            }
            return decoded
        } else {
            print("❌ 缓存数据解码失败")
            return []
        }
    }
    
    private func shouldSync() -> Bool {
        let calendar = Calendar.current
        return !calendar.isDateInToday(lastCalendarSyncDate)
    }
    
    private func setRestDay(date: Date) {
        let dateString = dateFormatter.string(from: date)
        print("\n🔄 设置休息日: \(dateString)")
        
        // 先更新本地状态
        if restDays.contains(dateString) {
            print("📝 移除休息日")
            restDays.removeAll { $0 == dateString }
        } else {
            print("📝 添加休息日")
            restDays.append(dateString)
        }
        
        // 保存到缓存
        print("💾 保存到本地缓存")
        saveToCache(restDays)
        
        // 更新数据库
        print("🔄 同步到数据库")
        let db = Firestore.firestore()
        db.collection("users")
            .document(userId)
            .collection("calendar")
            .document("restDays")
            .setData([
                "days": restDays,
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("❌ 数据库更新失败: \(error)")
                    return
                }
                print("✅ 数据库更新成功")
                self.lastCalendarSyncDate = Date()
            }
    }
    
    private func weekRangeText() -> String {
        let firstDate = weekDates.first ?? selectedDate
        let lastDate = weekDates.last ?? selectedDate
        return "\(firstDate.formatted(.dateTime.month().day()))-\(lastDate.formatted(.dateTime.month().day()))"
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    private func loadTrainingParts() {
        let db = Firestore.firestore()
        // 获取当前月份的开始和结束日期
        let calendar = Calendar.current
        let startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate)!
        
        db.collection("users")
            .document(userId)
            .collection("trainingParts")
            .whereField("date", isGreaterThanOrEqualTo: startDate)
            .whereField("date", isLessThanOrEqualTo: endDate)
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    for doc in documents {
                        if let bodyPart = doc.data()["bodyPart"] as? String,
                           let date = (doc.data()["date"] as? Timestamp)?.dateValue() {
                            trainingParts[date.formatDate()] = bodyPart
                        }
                    }
                }
            }
    }
    
    // 在日历单元格中显示训练部位
    private func calendarCell(date: Date) -> some View {
        VStack {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 16, weight: .medium))
            
            if let bodyPart = trainingParts[date.formatDate()] {
                Text(bodyPart)
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // ... 其他现有的训练标记
        }
    }
}

// 添加日期格式化扩展
extension Date {
    func formatDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}

// 美化日期单元格视图
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let hasTraining: Bool
    let isToday: Bool
    let isRestDay: Bool
    let onTap: () -> Void
    let setRestDay: (Date) -> Void
    let calendar: Calendar
    let trainingRecords: [String: [TrainingRecord]]
    let dateFormatter: DateFormatter
    
    @Binding var currentSwipedDate: Date?
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    @State private var isAnimating = false
    
    // 添加系统声音播放器
    private let soundPlayer = SystemSoundID(1519) // 系统声音: positive_change.caf
    
    var body: some View {
        ZStack {
            // 滑动显示的按钮
            HStack {
                Spacer()
                Button(action: {
                    // 播放系统声音
                    AudioServicesPlaySystemSound(soundPlayer)
                    
                    // 触发系统振动
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        setRestDay(date)
                        resetCell()
                    }
                }) {
                    VStack {
                        Image(systemName: isRestDay ? "figure.run" : "moon.zzz.fill")
                            .font(.system(size: 20))
                            .scaleEffect(isAnimating ? 1.1 : 1.0)
                            .rotation3DEffect(
                                .degrees(isRestDay ? 180 : 0),
                                axis: (x: 0, y: 1, z: 0)
                            )
                        Text(isRestDay ? "训练日" : "休息日")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .frame(maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isRestDay ? Color.blue : Color.orange)
                            .opacity(isAnimating ? 1 : 0.9)
                    )
                    .shadow(color: (isRestDay ? Color.blue : Color.orange).opacity(0.3),
                            radius: isAnimating ? 8 : 4,
                            x: 0,
                            y: 2)
                }
                .padding(.trailing, 16)
            }
            .zIndex(0)
            .opacity(offset < 0 ? 1 : 0)
            .offset(x: offset < -40 ? 20 : 40)
            
            // 主内容
            HStack {
                // 日期和星期
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(date.formatted(.dateTime.month(.defaultDigits)))月\(date.formatted(.dateTime.day(.defaultDigits)))日")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isToday ? .blue : .primary)
                    Text(date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 显示休息日或训练日状态
                if isRestDay {
                    Label("休息日", systemImage: "moon.zzz.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.1))
                        )
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: onTap) {
                        HStack(spacing: 6) {
                            if hasTraining {
                                Text("已训练")
                                    .foregroundColor(.green)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Text("训练日")
                                    .foregroundColor(.white)
                            }
                            Image(systemName: hasTraining ? "checkmark.circle.fill" : "figure.run")
                                .font(.system(size: 14, weight: .semibold))
                                .transition(.scale.combined(with: .opacity))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(hasTraining ? Color(.systemGreen).opacity(0.1) : Color.blue)
                        )
                        .foregroundColor(hasTraining ? .green : .white)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.trailing, 5)
                }
                
                if hasTraining, 
                   let records = trainingRecords[dateFormatter.string(from: date)] {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(records) { record in
                            Text(record.bodyPart)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05),
                            radius: isAnimating ? 6 : 4,
                            x: 0,
                            y: 2)
            )
            .offset(x: offset)
            .zIndex(1)
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        print("⚡️ Gesture onChanged - Current date: \(date)")
                        print("⚡️ currentSwipedDate: \(String(describing: currentSwipedDate))")
                        
                        // 如果开始新的滑动，且之前有其他单元格在滑动
                        if currentSwipedDate == nil {
                            print("✅ 设置当前滑动日期: \(date)")
                            currentSwipedDate = date
                        } else if let swipedDate = currentSwipedDate,
                                  !calendar.isDate(swipedDate, inSameDayAs: date) {
                            // 如果滑动新的单元格，重置之前的单元格
                            print("🔄 切换到新的单元格，重置之前的单元格")
                            currentSwipedDate = date
                        }
                        
                        // 处理左滑和右滑
                        if value.translation.width < 0 {
                            // 左滑打开
                            offset = max(value.translation.width, -80)
                            print("📏 左滑距离: \(offset)")
                        } else if isSwiped {
                            // 右滑关闭
                            let translation = min(80 + value.translation.width, 0)
                            offset = translation
                            print("📏 右滑恢复距离: \(translation)")
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if value.translation.width < -40 {
                                // 左滑超过阈值，保持打开状态
                                print("👆 手势结束 - 保持展开状态")
                                offset = -80
                                isSwiped = true
                            } else {
                                // 其他情况都恢复初始状态
                                print("👆 手势结束 - 恢复初始状态")
                                resetCell()
                            }
                        }
                    }
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                isAnimating = true
            }
        }
        .onChange(of: isRestDay) { oldValue, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isAnimating = true
            }
        }
        .onChange(of: currentSwipedDate) { oldValue, newValue in
            if let swipedDate = newValue,
               !calendar.isDate(swipedDate, inSameDayAs: date) {
                print("🔄 重置非当前滑动的单元格")
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    offset = 0
                    isSwiped = false
                }
            }
        }
        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .onDisappear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                offset = 0
                isSwiped = false
                if let swipedDate = currentSwipedDate,
                   calendar.isDate(swipedDate, inSameDayAs: date) {
                    currentSwipedDate = nil
                }
            }
        }
    }
    
    // 新增：重置单元格状态的辅助方法
    private func resetCell() {
        offset = 0
        isSwiped = false
        if let swipedDate = currentSwipedDate,
           calendar.isDate(swipedDate, inSameDayAs: date) {
            currentSwipedDate = nil
        }
    }
}

// 添加自定义按钮样式
struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
    }
}

#Preview {
    CalendarView()
} 
