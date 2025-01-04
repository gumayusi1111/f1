import SwiftUI
import FirebaseFirestore
import CryptoKit

struct LoginView: View {
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("lastLoginUser") private var lastLoginUser: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isRegistering = false
    @FocusState private var focusedField: Field?
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var contentOffset: CGFloat = 0
    @State private var passwordStrength: PasswordStrength = .empty
    @State private var showPasswordError = false
    @AppStorage("loginAttempts") private var loginAttempts: Int = 0
    @AppStorage("lastLoginAttemptTime") private var lastLoginAttemptTime: Double = 0
    @State private var isLocked = false
    @State private var lockoutEndTime: Date = Date()
    @AppStorage("lastLoginCredentials") private var lastLoginCredentials: Data = Data()
    @State private var isOfflineMode = false
    @State private var showOfflineAlert = false
    
    private let maxLoginAttempts = 5  // 最大尝试次数
    private let lockoutDuration: TimeInterval = 300  // 锁定时间（5分钟）
    
    // 用于标识输入框的枚举
    private enum Field {
        case username
        case password
    }
    
    // 添加密码强度枚举
    private enum PasswordStrength {
        case empty, weak, medium, strong
        
        var color: Color {
            switch self {
            case .empty: return .gray
            case .weak: return .red
            case .medium: return .orange
            case .strong: return .green
            }
        }
        
        var text: String {
            switch self {
            case .empty: return ""
            case .weak: return "弱"
            case .medium: return "中等"
            case .strong: return "强"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // 背景点击收起键盘
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    hideKeyboard()
                }
            
            // 背景渐变
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if userId.isEmpty {
                VStack(spacing: 30) {
                    // Logo 和标题
                    VStack(spacing: 10) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("健身记录")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text(isRegistering ? "创建新账号" : "欢迎回来")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 50)
                    
                    // 输入区域
                    VStack(spacing: 20) {
                        if !lastLoginUser.isEmpty && !isRegistering {
                            // 快捷登录按钮
                            Button(action: quickLogin) {
                                HStack {
                                    Image(systemName: "person.fill")
                                    Text("使用上次账号登录：\(lastLoginUser)")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(25)
                            }
                            .padding(.horizontal, 25)
                            
                            Text("或使用其他账号登录")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        TextField("用户名", text: $username)
                            .textFieldStyle(CustomTextFieldStyle(text: $username))
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .username)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .password
                            }
                            .padding(.horizontal, 25)
                            .id("usernameField")
                        
                        passwordSection
                        
                        Button(action: isRegistering ? register : login) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(isLocked ? Color.gray : (isRegistering ? Color.green : Color.blue))
                                    .frame(height: 50)
                                
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    if isLocked {
                                        HStack {
                                            Image(systemName: "lock.fill")
                                            Text("账号已锁定")
                                        }
                                        .foregroundColor(.white)
                                    } else {
                                        Text(isRegistering ? "注册" : "登录")
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        .disabled(username.isEmpty || password.isEmpty || isLoading || isLocked)
                        .padding(.horizontal, 25)
                        
                        Button(action: { isRegistering.toggle() }) {
                            Text(isRegistering ? "已有账号？点击登录" : "新用户？点击注册")
                                .font(.footnote)
                                .foregroundColor(.blue)
                        }
                        
                        if isRegistering {
                            Link("联系开发者: zhaojunxi222@gmail.com",
                                 destination: URL(string: "mailto:zhaojunxi222@gmail.com")!)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.top, 5)
                        }
                    }
                    .padding(.top, 30)
                    
                    Spacer()
                    
                    if isRegistering {
                        // 注册时显示用户协议
                        VStack(spacing: 10) {
                            Text("注册即表示同意")
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 5) {
                                Text("用户协议")
                                    .foregroundColor(.blue)
                                Text("和")
                                    .foregroundColor(.gray)
                                Text("隐私政策")
                                    .foregroundColor(.blue)
                            }
                        }
                        .font(.footnote)
                        .padding(.bottom, 20)
                    }
                }
                .padding(.vertical)
                .offset(y: contentOffset)
                .animation(.easeOut(duration: 0.25), value: contentOffset)
            } else {
                ContentView()
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: isRegistering) { oldValue, newValue in // 修复 onChange 警告
            clearInputs()
        }
        .onAppear {
            setupKeyboardNotifications()
        }
        .onDisappear {
            removeKeyboardNotifications()
        }
        .alert("离线模式", isPresented: $showOfflineAlert) {
            Button("确定") { }
        } message: {
            Text("当前处于离线模式,部分功能可能受限。\n数据将在恢复连接后自动同步。")
        }
        if isOfflineMode {
            HStack {
                Image(systemName: "wifi.slash")
                Text("离线模式")
                Text("·")
                Text("将在恢复连接后同步")
            }
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.8))
        }
    }
    
    private func hideKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), 
                                      to: nil, 
                                      from: nil, 
                                      for: nil)
    }
    
    private func clearInputs() {
        username = ""
        password = ""
        focusedField = nil
    }
    
    private func login() {
        Task {
            hideKeyboard()
            isLoading = true
            
            // 首先检查数据库连接
            let hasConnection = await checkDatabaseConnection()
            
            if !hasConnection {
                // 无法连接数据库,尝试离线登录
                if verifyOfflineLogin(username: username, password: password) {
                    isOfflineMode = true
                    showOfflineAlert = true
                    userId = "offline_\(username)"
                    userName = username
                    isLoading = false
                } else {
                    handleLoginFailure("离线登录失败: 用户名或密码错误")
                }
                return
            }
            
            // 检查是否被锁定
            if checkLockStatus() {
                let remainingTime = Int(lockoutDuration - (Date().timeIntervalSince1970 - lastLoginAttemptTime))
                DispatchQueue.main.async {
                    errorMessage = "账号已被锁定，请在\(remainingTime/60)分\(remainingTime%60)秒后重试"
                    showError = true
                    isLoading = false
                }
                return
            }
            
            do {
                // 在线登录逻辑
                let db = Firestore.firestore()
                let snapshot = try await db.collection("users")
                    .whereField("name", isEqualTo: username)
                    .getDocuments()
                
                if let document = snapshot.documents.first {
                    let data = document.data()
                    let storedHash = data["passwordHash"] as? String
                    
                    if storedHash == hashPassword(password) {
                        // 登录成功，重置计数
                        print("✅ 登录成功")
                        DispatchQueue.main.async {
                            loginAttempts = 0
                            userId = document.documentID
                            userName = username
                            lastLoginUser = username
                            clearInputs()
                            saveLoginCredentials(username: username, passwordHash: hashPassword(password))
                            isLoading = false
                        }
                    } else {
                        handleLoginFailure("密码错误")
                    }
                } else {
                    handleLoginFailure("用户不存在")
                }
            } catch {
                print("❌ 登录失败: \(error)")
                handleLoginFailure("登录失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func register() {
        Task {
            hideKeyboard()
            guard !username.isEmpty && !password.isEmpty else { return }
            
            // 添加密码长度验证
            guard password.count >= 6 else {
                DispatchQueue.main.async {
                    errorMessage = "密码至少需要6个字符"
                    showError = true
                }
                return
            }
            
            isLoading = true
            let db = Firestore.firestore()
            
            do {
                // 首先检查总用户数
                let snapshot = try await db.collection("users").getDocuments()
                
                // 检查用户数量是否已达到限制
                if snapshot.documents.count >= 2 {
                    DispatchQueue.main.async {
                        isLoading = false
                        errorMessage = "已达到最大用户数限制（2个），如需帮助请联系开发者"
                        showError = true
                    }
                    return
                }
                
                // 检查用户名是否存在
                let existingUsers = try await db.collection("users")
                    .whereField("name", isEqualTo: username)
                    .getDocuments()
                
                if !existingUsers.documents.isEmpty {
                    DispatchQueue.main.async {
                        isLoading = false
                        errorMessage = "用户名已存在，请使用其他名字"
                        showError = true
                    }
                    return
                }
                
                // 创建新用户
                let hashedPassword = hashPassword(password)
                let newUser: [String: Any] = [
                    "name": username,
                    "passwordHash": hashedPassword,
                    "createdAt": FieldValue.serverTimestamp(),
                    "friends": []
                ]
                
                // 添加新用户文档
                let docRef = try await db.collection("users").addDocument(data: newUser)
                
                print("✅ 用户注册成功")
                DispatchQueue.main.async {
                    userId = docRef.documentID
                    userName = username
                    lastLoginUser = username
                    isLoading = false
                    clearInputs()
                    // 保存登录凭证
                    saveLoginCredentials(username: username, passwordHash: hashedPassword)
                }
                
            } catch {
                print("❌ 注册失败: \(error)")
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = "创建用户失败: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    private func quickLogin() {
        Task {
            isLoading = true
            
            // 首先检查数据库连接
            let hasConnection = await checkDatabaseConnection()
            
            if !hasConnection {
                // 无法连接数据库,尝试离线快速登录
                print("\n📱 尝试离线快速登录")
                print("  上次登录用户: \(lastLoginUser)")
                
                // 验证上次登录的用户凭证
                guard let decoded = try? JSONDecoder().decode([String: String].self, from: lastLoginCredentials),
                      let storedUsername = decoded["username"],
                      storedUsername == lastLoginUser else {
                    DispatchQueue.main.async {
                        isLoading = false
                        errorMessage = "离线登录失败: 未找到有效的登录凭证"
                        showError = true
                    }
                    return
                }
                
                // 离线快速登录成功
                print("✅ 离线快速登录成功")
                DispatchQueue.main.async {
                    isOfflineMode = true
                    showOfflineAlert = true
                    userId = "offline_\(lastLoginUser)"
                    userName = lastLoginUser
                    isLoading = false
                }
                return
            }
            
            // 在线快速登录逻辑
            print("\n🌐 尝试在线快速登录")
            let db = Firestore.firestore()
            
            do {
                let snapshot = try await db.collection("users")
                    .whereField("name", isEqualTo: lastLoginUser)
                    .getDocuments()
                
                if let document = snapshot.documents.first {
                    print("✅ 快速登录成功")
                    DispatchQueue.main.async {
                        userId = document.documentID
                        userName = lastLoginUser
                        isLoading = false
                    }
                } else {
                    print("❌ 用户信息已失效")
                    DispatchQueue.main.async {
                        isLoading = false
                        errorMessage = "用户信息已失效，请重新登录"
                        showError = true
                    }
                }
            } catch {
                print("❌ 快速登录失败: \(error)")
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = "登录失败: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    // 密码加密函数
    private func hashPassword(_ password: String) -> String {
        let inputData = Data(password.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func setupKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
            
            // 修改这里的偏移量，减少上移距离
            let offset = -keyboardFrame.height + 200 // 增加底部保留空间到200
            
            withAnimation(.easeOut(duration: duration)) {
                contentOffset = offset
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
            
            withAnimation(.easeOut(duration: duration)) {
                contentOffset = 0
            }
        }
    }
    
    private func removeKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func checkUserLimit() async throws -> Bool {
        let db = Firestore.firestore()
        let snapshot = try await db.collection("users").getDocuments()
        return snapshot.documents.count < 2
    }
    
    // 添加密码验证函数
    private func validatePassword(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return .empty }
        
        let hasNumbers = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasLetters = password.rangeOfCharacter(from: .letters) != nil
        let hasSpecialChars = password.rangeOfCharacter(from: .punctuationCharacters) != nil
        
        if password.count < 6 {
            return .weak
        }
        
        if hasNumbers && hasLetters && hasSpecialChars && password.count >= 8 {
            return .strong
        }
        
        if (hasNumbers && hasLetters) || (hasLetters && hasSpecialChars) || (hasNumbers && hasSpecialChars) {
            return .medium
        }
        
        return .weak
    }
    
    // 修改密码输入框部分
    var passwordSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SecureField("密码", text: $password)
                    .textFieldStyle(CustomTextFieldStyle(text: $password))
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onChange(of: password) { _, newValue in
                        passwordStrength = validatePassword(newValue)
                        showPasswordError = isRegistering && newValue.count < 6
                    }
                    .onSubmit {
                        hideKeyboard()
                        if !username.isEmpty && !password.isEmpty && !showPasswordError {
                            isRegistering ? register() : login()
                        }
                    }
            }
            .padding(.horizontal, 25)
            
            if isRegistering && focusedField == .password && !password.isEmpty {
                VStack(spacing: 8) {
                    // 密码强度进度条
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Capsule()
                                .frame(height: 4)
                                .foregroundColor(getStrengthColor(for: index))
                                .animation(.easeInOut, value: passwordStrength)
                        }
                    }
                    .frame(width: 120)
                    .padding(.top, 4)
                    
                    // 密码强度文本
                    HStack(spacing: 4) {
                        Circle()
                            .fill(passwordStrength.color)
                            .frame(width: 6, height: 6)
                        
                        Text(passwordStrength.text)
                            .font(.caption2)
                            .foregroundColor(passwordStrength.color)
                    }
                    
                    if showPasswordError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text("密码至少需要6个字符")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 25)
                .transition(.opacity)
            }
        }
    }
    
    // 添加辅助函数来获取强度条颜色
    private func getStrengthColor(for index: Int) -> Color {
        switch (passwordStrength, index) {
        case (.strong, _):
            return .green
        case (.medium, 0), (.medium, 1):
            return .orange
        case (.weak, 0):
            return .red
        default:
            return .gray.opacity(0.3)
        }
    }
    
    // 添加检查是否被锁定的函数
    private func checkLockStatus() -> Bool {
        if loginAttempts >= maxLoginAttempts {
            let timeSinceLastAttempt = Date().timeIntervalSince1970 - lastLoginAttemptTime
            if timeSinceLastAttempt < lockoutDuration {
                isLocked = true
                lockoutEndTime = Date(timeIntervalSince1970: lastLoginAttemptTime + lockoutDuration)
                return true
            } else {
                // 锁定时间已过，重置计数
                loginAttempts = 0
                isLocked = false
                return false
            }
        }
        return false
    }
    
    // 处理登录失败
    private func handleLoginFailure(_ message: String) {
        loginAttempts += 1
        lastLoginAttemptTime = Date().timeIntervalSince1970
        
        if loginAttempts >= maxLoginAttempts {
            errorMessage = "登录失败次数过多，账号已被锁定5分钟"
        } else {
            errorMessage = "\(message)\n还剩\(maxLoginAttempts - loginAttempts)次尝试机会"
        }
        showError = true
        password = ""  // 只清空密码
        isLoading = false
    }
    
    // 添加检查网络连接状态的函数
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
    
    // 修改登录成功后的凭证保存
    private func saveLoginCredentials(username: String, passwordHash: String) {
        let credentials = ["username": username, "passwordHash": passwordHash]
        if let encoded = try? JSONEncoder().encode(credentials) {
            lastLoginCredentials = encoded
        }
    }
    
    // 添加离线登录验证
    private func verifyOfflineLogin(username: String, password: String) -> Bool {
        print("\n🔐 验证离线登录:")
        print("  用户名: \(username)")
        
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: lastLoginCredentials),
              let storedUsername = decoded["username"],
              let storedPasswordHash = decoded["passwordHash"] else {
            print("❌ 未找到本地登录凭证")
            return false
        }
        
        print("📝 本地凭证信息:")
        print("  存储的用户名: \(storedUsername)")
        
        let result = username == storedUsername && hashPassword(password) == storedPasswordHash
        print(result ? "✅ 验证成功" : "❌ 验证失败")
        return result
    }
}

// 自定义文本框样式
struct CustomTextFieldStyle: TextFieldStyle {
    @Binding var text: String
    var showClearButton: Bool = true
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        HStack {
            configuration
                .padding(.vertical, 20)
                .padding(.horizontal, 15)
            
            if !text.isEmpty && showClearButton {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray.opacity(0.5))
                        .frame(width: 20, height: 20)
                }
                .padding(.trailing, 15)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white)
                .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 2)
        )
    }
} 