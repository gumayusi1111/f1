import SwiftUI

// MARK: - RefreshableView
struct RefreshableView<Content: View>: View {
    // MARK: - Properties
    private let content: Content
    private let onRefresh: @Sendable () async -> Void
    private let refreshThreshold: CGFloat = 60
    
    @State private var isRefreshing = false
    @State private var refreshOffset: CGFloat = 0
    @State private var pullOffset: CGFloat = 0
    @State private var lastRefreshTime: Date?
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // 动画相关状态
    @State private var rotationDegree: Double = 0
    @State private var indicatorOpacity: Double = 0
    
    // 添加刷新限制相关属性
    private let minimumRefreshInterval: TimeInterval = 60 // 1分钟刷新限制
    @State private var lastRefreshAttempt: Date?
    
    // MARK: - Initialization
    init(
        @ViewBuilder content: () -> Content,
        onRefresh: @escaping @Sendable () async -> Void
    ) {
        self.content = content()
        self.onRefresh = onRefresh
        print("📱 RefreshableView initialized")
    }
    
    // MARK: - Body
    var body: some View {
        ScrollView {
            refreshHeader
            content
                .offset(y: isRefreshing ? refreshThreshold : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isRefreshing)
        }
        .background(scrollOffsetReader)
        .onPreferenceChange(OffsetPreferenceKey.self) { offset in
            refreshOffset = offset
            // 降低灵敏度，只在明显的下拉时触发
            let newPullOffset = max(0, -offset)
            if abs(newPullOffset - pullOffset) > 1 { // 添加阈值
                pullOffset = newPullOffset
                
                if pullOffset > 0 {
                    print("⬇️ Pulling: \(String(format: "%.1f", pullOffset))pt")
                }
                
                withAnimation(.linear(duration: 0.2)) {
                    indicatorOpacity = min(1, pullOffset / refreshThreshold)
                    rotationDegree = min(180, pullOffset * 3) // 增加旋转速度
                }
            }
        }
        .alert("提示", isPresented: $showingError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }
    
    // MARK: - Helper Views
    private var refreshHeader: some View {
        GeometryReader { geometry in
            if geometry.frame(in: .global).minY > refreshThreshold && !isRefreshing {
                Spacer()
                    .onAppear {
                        startRefresh()
                    }
            }
            
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    ZStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees(
                                min(180, rotationDegree)
                            ))
                            .scaleEffect(
                                pullOffset > 0 ? 
                                    min(1.2, 1 + pullOffset / (refreshThreshold * 2)) : 1
                            )
                            .opacity(isRefreshing ? 0 : indicatorOpacity)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .opacity(isRefreshing ? 1 : 0)
                            .scaleEffect(isRefreshing ? 1.2 : 0.5)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: rotationDegree)
                    
                    Text(refreshStatusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .animation(.easeInOut, value: isRefreshing)
                        .offset(y: -13)
                }
                .frame(height: 80)
                Spacer()
            }
            .offset(y: -geometry.frame(in: .global).minY)
        }
        .frame(height: 0)
    }
    
    private var scrollOffsetReader: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: OffsetPreferenceKey.self,
                value: geometry.frame(in: .named("scroll")).origin.y
            )
        }
    }
    
    // MARK: - Helper Methods
    private func startRefresh() {
        // 检查是否可以执行刷新操作
        if let lastAttempt = lastRefreshAttempt,
           Date().timeIntervalSince(lastAttempt) < minimumRefreshInterval {
            // 如果在限制时间内，只重置UI状态，不执行刷新
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isRefreshing = false
            }
            return
        }
        
        lastRefreshAttempt = Date()
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isRefreshing = true
        }
        
        Task {
            do {
                let startTime = Date()
                try await withTimeout(operation: onRefresh)
                
                let endTime = Date()
                let minimumDuration: TimeInterval = 0.5
                let actualDuration = endTime.timeIntervalSince(startTime)
                
                if actualDuration < minimumDuration {
                    try await Task.sleep(for: .seconds(minimumDuration - actualDuration))
                }
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isRefreshing = false
                        lastRefreshTime = Date()
                    }
                }
                print("✅ 刷新完成")
                
            } catch {
                print("❌ 刷新失败: \(error.localizedDescription)")
                await MainActor.run {
                    showError("刷新失败，请稍后重试")
                    withAnimation {
                        isRefreshing = false
                    }
                }
            }
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    private func withTimeout<T>(timeout: TimeInterval = 30, operation: @escaping () async -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }
            
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Computed Properties
    private var refreshStatusText: String {
        if let lastAttempt = lastRefreshAttempt,
           Date().timeIntervalSince(lastAttempt) < minimumRefreshInterval {
            let remainingTime = Int(minimumRefreshInterval - Date().timeIntervalSince(lastAttempt))
            return "\(remainingTime)秒后可刷新"
        } else if isRefreshing {
            return "正在刷新..."
        } else if pullOffset > refreshThreshold {
            return "松手刷新"
        } else if pullOffset > 0 {
            return "继续下拉"
        } else if let lastTime = lastRefreshTime {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "上次刷新: \(formatter.localizedString(for: lastTime, relativeTo: Date()))"
        } else {
            return "下拉刷新"
        }
    }
}

// MARK: - Error Types
private struct TimeoutError: LocalizedError {
    var errorDescription: String? {
        return "操作超时"
    }
}

// MARK: - Preference Key
private struct OffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview
struct RefreshableView_Previews: PreviewProvider {
    static var previews: some View {
        RefreshableView {
            VStack {
                ForEach(0..<20) { i in
                    Text("Item \(i)")
                        .padding()
                }
            }
        } onRefresh: {
            print("🔄 模拟网络请求...")
            try? await Task.sleep(for: .seconds(2))
            print("✅ 模拟请求完成")
        }
    }
} 