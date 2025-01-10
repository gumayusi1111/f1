import SwiftUI
import FirebaseFirestore

struct ProfileView: View {
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("lastLoginUser") private var lastLoginUser: String = ""  // 记录上次登录用户
    @AppStorage("userAvatar") private var userAvatar: String = "" // 存储头像URL
    @AppStorage("localAvatarData") private var localAvatarData: Data?
    @AppStorage("cachedAvatarData") private var cachedAvatarData: Data = Data()
    @AppStorage("lastAvatarSyncDate") private var lastAvatarSyncDate: Date = .distantPast
    
    @State private var friends: [User] = []
    @State private var showLogoutAlert = false
    
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    @State private var cachedUIImage: UIImage?
    @State private var selectedStatus: User.OnlineStatus = .offline
    
    // 1. 添加新的持久化存储键
    private let AVATAR_CACHE_KEY = "userAvatarCache_"
    
    var body: some View {
        NavigationView {
            List {
                Section("个人信息") {
                    HStack {
                        avatarImage
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // 用户名
                            Text(userName)
                                .font(.headline)
                            
                            // 用户 ID
                            Text("ID: \(userId)")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            // 在线状态
                            HStack(spacing: 6) {
                                Image(systemName: statusIcon(selectedStatus))
                                    .foregroundColor(statusColor(selectedStatus))
                                    .font(.system(size: 12))
                                
                                Text(statusText(selectedStatus))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        Text("更换头像")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 8)
                    
                    Picker("在线状态", selection: $selectedStatus) {
                        Text("在线")
                            .tag(User.OnlineStatus.online)
                        Text("离开")
                            .tag(User.OnlineStatus.away)
                        Text("离线")
                            .tag(User.OnlineStatus.offline)
                    }
                    .onChange(of: selectedStatus) { oldValue, newValue in
                        updateOnlineStatus(newValue)
                    }
                }
                
                Section("社交") {
                    NavigationLink {
                        AddFriendView()
                    } label: {
                        HStack {
                            Text("添加好友")
                            Spacer()
                            Image(systemName: "person.badge.plus")
                        }
                    }
                    
                    NavigationLink {
                        FriendListView()
                    } label: {
                        HStack {
                            Text("好友列表")
                            Spacer()
                            Image(systemName: "person.2")
                        }
                    }
                    
                    NavigationLink {
                        FriendRequestsView()
                    } label: {
                        HStack {
                            Text("好友请求")
                            Spacer()
                            Image(systemName: "person.2.circle")
                        }
                    }
                    
                    NavigationLink {
                        FriendRankingView()
                    } label: {
                        HStack {
                            Text("好友排行")
                            Spacer()
                            Image(systemName: "chart.bar.fill")
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        showLogoutAlert = true
                    }) {
                        HStack {
                            Text("退出登录")
                                .foregroundColor(.red)
                            Spacer()
                            Image(systemName: "arrow.right.square")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("个人中心")
            .alert("确认退出", isPresented: $showLogoutAlert) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    logout()
                }
            } message: {
                Text("确定要退出登录吗？")
            }
            .alert("上传失败", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("上传成功", isPresented: $showSuccess) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("头像已更新")
            }
            .onAppear {
                print("\n========== 进入个人中心页面 ==========")
                loadAvatar()  // 加载头像
                loadUserInfo()  // 加载用户信息
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            if let image = newValue {
                handleImageSelection(image)
            }
        }
        .overlay(
            Group {
                if isUploading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay(
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                        )
                }
            }
        )
    }
    
    private func logout() {
        print("\n========== 开始退出登录 ==========")
        
        // 1. 先禁用界面交互,防止重复操作
        isUploading = true
        
        // 2. 保存最后登录的用户信息
        lastLoginUser = userName
        print("✅ 保存最后登录用户: \(userName)")
        
        // 3. 清除头像缓存前，确保保存到持久化存储
        let cacheKey = AVATAR_CACHE_KEY + userId
        if let currentImage = cachedUIImage,
           let imageData = currentImage.jpegData(compressionQuality: 0.5) {
            UserDefaults.standard.set(imageData, forKey: cacheKey)
        }
        
        // 清除内存缓存
        cachedAvatarData = Data()
        localAvatarData = nil
        selectedImage = nil
        cachedUIImage = nil
        _ = ImageCache.shared.getImage(forKey: userId)
        
        // 4. 清除其他数据
        friends = []
        print("✅ 清除好友列表")
        
        // 5. 使用延迟确保其他操作完成后再清除用户凭证
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // 清除用户凭证
            self.userName = ""
            self.userId = ""
            
            // 恢复界面交互
            self.isUploading = false
            
            print("✅ 清除用户凭证")
            print("========== 退出登录完成 ==========\n")
        }
        
        // 更新状态为离线
        let db = Firestore.firestore()
        db.collection("users").document(userId)
            .updateData([
                "onlineStatus": User.OnlineStatus.offline.rawValue,
                "lastStatusUpdate": FieldValue.serverTimestamp()
            ])
    }
    
    private func handleImageSelection(_ image: UIImage) {
        print("\n🔄 选择了新头像")
        updateAvatar(with: image)
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
        isUploading = false
    }
    
    private func compressImage(_ image: UIImage, maxSizeKB: Int = 100) -> Data? {
        var compression: CGFloat = 1.0
        let maxBytes = maxSizeKB * 1024
        
        guard var imageData = image.jpegData(compressionQuality: compression) else {
            return nil
        }
        
        while imageData.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            if let compressedData = image.jpegData(compressionQuality: compression) {
                imageData = compressedData
            }
        }
        
        return imageData
    }
    
    private var avatarImage: some View {
        Group {
            if let uiImage = selectedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let cachedImage = cachedUIImage {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFill()
            } else if !cachedAvatarData.isEmpty,
                      let uiImage = UIImage(data: cachedAvatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let cachedImage = ImageCache.shared.getImage(forKey: userId) {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
    }
    
    private func loadAvatar() {
        print("\n========== 开始加载头像 ==========")
        
        // 1. 先尝试从本地持久化存储加载
        let cacheKey = AVATAR_CACHE_KEY + userId
        if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let cachedImage = UIImage(data: cachedData) {
            print("✅ 从本地存储加载头像成功")
            self.cachedAvatarData = cachedData
            self.cachedUIImage = cachedImage
            ImageCache.shared.setImage(cachedImage, forKey: userId)
            return
        }
        
        // 2. 如果本地没有，从 Firestore 加载
        print("📥 从服务器加载头像...")
        let db = Firestore.firestore()
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                print("❌ 加载失败: \(error.localizedDescription)")
                return
            }
            
            if let data = snapshot?.data(),
               let avatarBase64 = data["avatar_base64"] as? String,
               let imageData = Data(base64Encoded: avatarBase64),
               let image = UIImage(data: imageData) {
                
                // 保存到本地存储
                UserDefaults.standard.set(imageData, forKey: cacheKey)
                
                // 更新内存缓存
                DispatchQueue.main.async {
                    self.cachedAvatarData = imageData
                    self.cachedUIImage = image
                    ImageCache.shared.setImage(image, forKey: self.userId)
                    print("✅ 从服务器加载头像成功")
                }
            }
        }
    }
    
    private func updateAvatar(with image: UIImage) {
        print("\n🔄 开始更新头像...")
        isUploading = true  // 显示加载状态
        
        // 1. 压缩图片
        guard let imageData = compressImage(image, maxSizeKB: 100) else {
            print("❌ 图片压缩失败")
            showError(message: "图片处理失败")
            return
        }
        
        let sizeKB = Double(imageData.count) / 1024.0
        print("📊 图片大小: \(String(format: "%.2f", sizeKB))KB")
        
        if sizeKB > 100 {
            print("❌ 图片太大")
            showError(message: "图片太大，请选择较小的图片")
            return
        }
        
        // 2. 保存到本地持久化存储
        let cacheKey = AVATAR_CACHE_KEY + userId
        UserDefaults.standard.set(imageData, forKey: cacheKey)
        
        // 3. 更新内存缓存
        cachedAvatarData = imageData
        selectedImage = image
        cachedUIImage = image
        ImageCache.shared.setImage(image, forKey: userId)
        
        print("💾 保存到本地缓存成功")
        
        // 4. 更新到 Firestore
        let base64String = imageData.base64EncodedString()
        let db = Firestore.firestore()
        
        print("📤 开始上传到服务器...")
        db.collection("users").document(userId).updateData([
            "avatar_base64": base64String,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ 服务器更新失败: \(error.localizedDescription)")
                    self.showError(message: "上传失败：\(error.localizedDescription)")
                } else {
                    print("✅ 服务器更新成功")
                    self.userAvatar = base64String
                    self.lastAvatarSyncDate = Date()
                    self.showSuccess = true
                }
                self.isUploading = false
            }
        }
    }
    
    private func loadUserInfo() {
        print("\n📱 当前用户信息:")
        print("  - 用户ID: \(userId)")
        print("  - 用户名: \(userName)")
        
        // 加载在线状态
        let db = Firestore.firestore()
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let data = snapshot?.data(),
               let statusString = data["onlineStatus"] as? String,
               let status = User.OnlineStatus(rawValue: statusString) {
                selectedStatus = status
            }
        }
    }
    
    private func updateOnlineStatus(_ status: User.OnlineStatus) {
        let db = Firestore.firestore()
        db.collection("users").document(userId)
            .updateData([
                "onlineStatus": status.rawValue,
                "lastStatusUpdate": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("Error updating status: \(error)")
                }
            }
    }
    
    private func clearCache() {
        cachedAvatarData = Data()
        localAvatarData = nil
        selectedImage = nil
        cachedUIImage = nil
        ImageCache.shared.removeImage(forKey: userId)
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
}

// 图片选择器
struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @Binding var image: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, UIImage>()
    
    func setImage(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    func getImage(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }
} 