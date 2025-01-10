import SwiftUI
import FirebaseFirestore

struct FriendDetailView: View {
    let friend: User
    @Environment(\.dismiss) private var dismiss
    @State private var showRemoveAlert = false
    @AppStorage("userId") private var userId: String = ""
    @State private var workoutDays: [Date] = []
    @State private var isLoadingWorkouts = true
    @State private var maxConsecutiveDays: Int = 0
    @State private var mostFrequentBodyPart: String = "加载中..."
    @State private var mostFrequentWorkoutTime: String = "加载中..."
    @State private var workoutTags: [String] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Group {
                    // 1. 头像和基本信息部分
                    profileHeader
                        .frame(maxWidth: .infinity)
                    
                    // 2. 数据统计部分
                    statsOverview
                        .frame(maxWidth: .infinity)
                    
                    // 3. 本周活跃度
                    weeklyActivitySection
                        .frame(maxWidth: .infinity)
                    
                    // 4. 运动标签
                    VStack(spacing: 16) {
                        Text("运动标签")
                            .font(.title2)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if workoutTags.isEmpty {
                            Text("暂无标签")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ForEach(workoutTags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.subheadline)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(tagColor(for: tag).opacity(0.1))
                                        )
                                        .foregroundColor(tagColor(for: tag))
                                }
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                    )
                    .frame(maxWidth: .infinity)
                }
                
                // 5. 操作按钮部分
                if friend.id != userId {
                    actionSection
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle("好友详情")
        .alert("确认删除", isPresented: $showRemoveAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                removeFriend()
            }
        } message: {
            Text("确定要删除该好友吗？")
        }
        .task {
            loadFriendDetails()
        }
    }
    
    // 新的头像和基本信息布局
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // 头像
            if let avatarData = Data(base64Encoded: friend.avatar_base64 ?? ""),
               let uiImage = UIImage(data: avatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(statusColor(friend.onlineStatus), lineWidth: 4))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.gray)
            }
            
            // 用户名和状态
            VStack(spacing: 8) {
                Text(friend.username)
                    .font(.title)
                    .bold()
                
                HStack {
                    Circle()
                        .fill(statusColor(friend.onlineStatus))
                        .frame(width: 8, height: 8)
                    Text(statusText(friend.onlineStatus))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }
    
    // 数据统计概览
    private var statsOverview: some View {
        VStack(spacing: 16) {
            Text("运动数据")
                .font(.title2)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                statsCard(
                    title: "累计运动",
                    value: "\(workoutDays.count)",
                    unit: "天",
                    icon: "figure.run",
                    color: .blue
                )
                
                statsCard(
                    title: "最长连续",
                    value: "\(maxConsecutiveDays)",
                    unit: "天",
                    icon: "flame.fill",
                    color: .orange
                )
                
                statsCard(
                    title: "常练部位",
                    value: mostFrequentBodyPart,
                    unit: "",
                    icon: "figure.strengthtraining.traditional",
                    color: .purple
                )
                
                statsCard(
                    title: "常用时段",
                    value: mostFrequentWorkoutTime,
                    unit: "",
                    icon: "clock.fill",
                    color: .green
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }
    
    // 改进的统计卡片样式
    private func statsCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(color.opacity(0.1))
                )
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .bold()
                    .foregroundColor(color)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: color.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
    
    // 改进的周活跃度图表
    private var weeklyActivitySection: some View {
        VStack(spacing: 16) {
            Text("本周活跃度")
                .font(.title2)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isLoadingWorkouts {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                weeklyActivityChart
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }
    
    // 改进的操作按钮
    private var actionSection: some View {
        Button(action: {
            showRemoveAlert = true
        }) {
            HStack {
                Image(systemName: "person.badge.minus")
                Text("删除好友")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.red)
            )
            .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
    
    private func removeFriend() {
        let db = Firestore.firestore()
        
        // 1. 从当前用户的好友列表中移除
        db.collection("users").document(userId).updateData([
            "friendIds": FieldValue.arrayRemove([friend.id])
        ])
        
        // 2. 从好友的好友列表中移除当前用户
        db.collection("users").document(friend.id).updateData([
            "friendIds": FieldValue.arrayRemove([userId])
        ]) { error in
            if error == nil {
                // 3. 返回上一页
                dismiss()
            }
        }
    }
    
    private func statusIcon(_ status: User.OnlineStatus) -> String {
        switch status {
        case .online: return "circle.fill"
        case .away: return "moon.fill"
        case .offline: return "circle.slash"
        }
    }
    
    private func statusColor(_ status: User.OnlineStatus) -> Color {
        switch status {
        case .online: return .green
        case .away: return .yellow
        case .offline: return .gray
        }
    }
    
    private func statusText(_ status: User.OnlineStatus) -> String {
        switch status {
        case .online: return "在线"
        case .away: return "离开"
        case .offline: return "离线"
        }
    }
    
    // 修改周活跃度图表计算方法
    private func getWeeklyWorkouts() -> [Bool] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekDays = (0..<7).map { day in
            calendar.date(byAdding: .day, value: -day, to: today)!
        }.reversed()
        
        return weekDays.map { date in
            workoutDays.contains { calendar.isDate($0, inSameDayAs: date) }
        }
    }
    
    private var weeklyActivityChart: some View {
        let weeklyData = getWeeklyWorkouts()
        
        return HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(weeklyData[index] ? Color.green : Color.gray.opacity(0.2))
                        .frame(height: 32)
                    
                    Text(getWeekdayName(for: index))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func getWeekdayName(for index: Int) -> String {
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        let today = Calendar.current.component(.weekday, from: Date())
        let adjustedIndex = (today - 1 + index) % 7
        return weekdays[adjustedIndex]
    }
    
    private func formatDuration(_ days: Int) -> String {
        if days < 30 {
            return "\(days)"  // 如果小于30天,直接显示天数
        } else {
            let months = Double(days) / 30.0
            return String(format: "%.1f", months)  // 如果超过30天,显示月份(保留一位小数)
        }
    }
    
    // 添加新的加载函数
    private func loadFriendDetails() {
        let startTime = Date()
        print("\n📱 开始加载好友详情 [\(Date().formatted(.dateTime))]")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 加载目标: \(friend.username) [\(friend.id)]")
        
        let db = Firestore.firestore()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // 用于收集所有数据
        var allWorkoutDays: Set<Date> = []
        var bodyPartsCount: [String: Int] = [:]
        var trainingTimes: [Date] = []
        let group = DispatchGroup()
        
        // 指定要检查的日期
        let datesToCheck = [
            "2025-01-06",
            "2025-01-07",
            "2025-01-08"
        ]
        
        print("\n🔍 开始收集训练数据...")
        
        for dateString in datesToCheck {
            group.enter()
            
            // 1. 获取训练记录
            db.collection("users")
                .document(friend.id)
                .collection("trainings")
                .document(dateString)
                .collection("records")
                .getDocuments { snapshot, error in
                    defer { group.leave() }
                    
                    if let error = error {
                        print("❌ 获取记录失败 [\(dateString)]: \(error.localizedDescription)")
                        return
                    }
                    
                    if let documents = snapshot?.documents, !documents.isEmpty {
                        // 添加训练日期
                        if let date = dateFormatter.date(from: dateString) {
                            allWorkoutDays.insert(date)
                        }
                        
                        // 收集训练部位数据
                        documents.forEach { doc in
                            let data = doc.data()
                            if let bodyPart = data["bodyPart"] as? String {
                                bodyPartsCount[bodyPart, default: 0] += 1
                            }
                            
                            // 收集训练时间
                            if let timestamp = data["createdAt"] as? Timestamp {
                                trainingTimes.append(timestamp.dateValue())
                            }
                        }
                        
                        print("✅ 处理 \(dateString) 的 \(documents.count) 条记录")
                    }
                }
        }
        
        group.notify(queue: .main) {
            let loadTime = Date().timeIntervalSince(startTime)
            
            // 计算统计数据
            let sortedDates = Array(allWorkoutDays).sorted()
            let maxConsecutive = self.calculateMaxConsecutiveDays(sortedDates)
            let mostFrequentPart = bodyPartsCount.max(by: { $0.value < $1.value })?.key ?? "未知"
            
            // 计算平均训练时间
            let calendar = Calendar.current
            let averageHour = trainingTimes.reduce(0.0) { sum, date in
                return sum + Double(calendar.component(.hour, from: date))
            } / Double(trainingTimes.count)
            let adjustedHour = Int((averageHour + 2.0).rounded())
            let timeString = String(format: "%02d:00", adjustedHour)
            
            print("\n📊 数据统计结果:")
            print("  - 总训练天数: \(allWorkoutDays.count)")
            print("  - 最长连续: \(maxConsecutive)天")
            print("  - 常练部位: \(mostFrequentPart)")
            print("  - 常用时段: \(timeString)")
            
            // 生成标签
            var newTags: [String] = []
            
            // 基于总训练天数的标签
            if allWorkoutDays.count >= 100 {
                newTags.append("训练百日王")
            } else if allWorkoutDays.count >= 30 {
                newTags.append("训练月度达人")
            } else if allWorkoutDays.count >= 7 {
                newTags.append("训练周常客")
            } else if allWorkoutDays.count > 0 {
                newTags.append("训练新手")
            }
            
            // 基于连续训练的标签
            if maxConsecutive >= 30 {
                newTags.append("铁人意志")
            } else if maxConsecutive >= 7 {
                newTags.append("坚持不懈")
            } else if maxConsecutive >= 3 {
                newTags.append("初显毅力")
            }
            
            // 基于训练部位的标签
            if let (mostPart, count) = bodyPartsCount.max(by: { $0.value < $1.value }) {
                if count >= 20 {
                    newTags.append("\(mostPart)狂人")
                } else if count >= 10 {
                    newTags.append("\(mostPart)达人")
                } else if count >= 5 {
                    newTags.append("\(mostPart)爱好者")
                }
            }
            
            self.workoutTags = newTags
            
            // 更新UI
            DispatchQueue.main.async {
                self.workoutDays = sortedDates
                self.maxConsecutiveDays = maxConsecutive
                self.mostFrequentBodyPart = mostFrequentPart
                self.mostFrequentWorkoutTime = timeString
                self.isLoadingWorkouts = false
            }
            
            print("\n⏱️ 加载完成")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("总耗时: \(String(format: "%.2f", loadTime))秒")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
    }
    
    // 计算最长连续天数
    private func calculateMaxConsecutiveDays(_ dates: [Date]) -> Int {
        guard !dates.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        var maxConsecutive = 1
        var currentConsecutive = 1
        
        for i in 1..<dates.count {
            let days = calendar.dateComponents([.day], from: dates[i-1], to: dates[i]).day ?? 0
            if days == 1 {
                currentConsecutive += 1
                maxConsecutive = max(maxConsecutive, currentConsecutive)
            } else {
                currentConsecutive = 1
            }
        }
        
        return maxConsecutive
    }
    
    // 3. 添加标签颜色函数
    private func tagColor(for tag: String) -> Color {
        if tag.contains("王") || tag.contains("狂人") {
            return .orange
        } else if tag.contains("达人") {
            return .blue
        } else if tag.contains("新") {
            return .green
        } else {
            return .purple
        }
    }
}

// 添加 FlowLayout 用于标签自动换行
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: frame.origin, proposal: ProposedViewSize(frame.size))
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let viewSize = subview.sizeThatFits(.unspecified)
                
                if currentX + viewSize.width > width {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: viewSize.width, height: viewSize.height))
                lineHeight = max(lineHeight, viewSize.height)
                currentX += viewSize.width + spacing
                size.width = max(size.width, currentX)
            }
            size.height = currentY + lineHeight
        }
    }
} 