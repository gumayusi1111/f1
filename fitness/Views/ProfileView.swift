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
    @State private var showAddFriend = false
    @State private var showLogoutAlert = false
    
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    @State private var cachedUIImage: UIImage?
    
    var body: some View {
        NavigationView {
            List {
                Section("个人信息") {
                    HStack {
                        avatarImage
                        
                        VStack(alignment: .leading) {
                            Text(userName)
                                .font(.headline)
                            Text("ID: \(userId)")
                                .font(.caption)
                                .foregroundColor(.gray)
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
                }
                
                Section("好友列表") {
                    ForEach(friends) { friend in
                        HStack {
                            Text(friend.name)
                            Spacer()
                            Text("查看")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Button("添加好友") {
                        showAddFriend = true
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
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
            }
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
        // 保存最后登录的用户信息
        lastLoginUser = userName
        
        // 清除当前登录状态
        userId = ""
        userName = ""
        
        // 清除其他需要清除的数据
        friends = []
    }
    
    private func handleImageSelection(_ image: UIImage) {
        print("\n🔄 选择了新头像")
        updateAvatar(with: image)  // 使用新的更新方法
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
        isUploading = false
    }
    
    private func saveImage(_ image: UIImage) {
        print("\n📸 开始保存头像...")
        isUploading = true
        
        guard let imageData = compressImage(image, maxSizeKB: 100) else {
            print("❌ 图片压缩失败")
            showError(message: "图片处理失败")
            return
        }
        
        let sizeKB = Double(imageData.count) / 1024.0
        print("📊 图片信息:")
        print("  - 大小: \(String(format: "%.2f", sizeKB))KB")
        
        if sizeKB > 100 {
            print("❌ 图片太大")
            showError(message: "图片太大，请选择较小的图片")
            return
        }
        
        // 保存到本地
        localAvatarData = imageData
        
        // 转换为 Base64 字符串
        let base64String = imageData.base64EncodedString()
        
        // 保存到 Firestore
        let db = Firestore.firestore()
        db.collection("users")
            .document(userId)
            .setData([
                "avatar_base64": base64String
            ], merge: true) { error in
                if let error = error {
                    showError(message: "保存失败：\(error.localizedDescription)")
                } else {
                    DispatchQueue.main.async {
                        userAvatar = base64String
                        isUploading = false
                        showSuccess = true
                    }
                    if let image = UIImage(data: imageData) {
                        ImageCache.shared.setImage(image, forKey: userId)
                    }
                }
            }
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
            if let uiImage = selectedImage ?? cachedUIImage ?? (cachedAvatarData.isEmpty ? nil : UIImage(data: cachedAvatarData)) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let cachedImage = ImageCache.shared.getImage(forKey: userId) {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFill()
            } else if !userAvatar.isEmpty,
                      let imageData = Data(base64Encoded: userAvatar),
                      let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
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
        print("⏰ 当前时间: \(Date())")
        print("📅 上次同步时间: \(lastAvatarSyncDate)")
        
        let shouldSyncData = !Calendar.current.isDateInToday(lastAvatarSyncDate)
        print("🔍 检查是否需要同步:")
        print("  - 上次同步是否是今天: \(!shouldSyncData)")
        print("  - 需要同步: \(shouldSyncData)")
        
        if shouldSyncData {
            print("\n🔄 从数据库加载头像...")
            let db = Firestore.firestore()
            db.collection("users").document(userId).getDocument { snapshot, error in
                if let error = error {
                    print("❌ 数据库加载失败: \(error)")
                    print("📦 使用本地缓存作为备选")
                    loadAvatarFromCache()
                    return
                }
                
                if let data = snapshot?.data(),
                   let avatarBase64 = data["avatar_base64"] as? String,
                   let imageData = Data(base64Encoded: avatarBase64) {
                    print("✅ 数据库加载成功")
                    saveAvatarToCache(imageData)
                    self.lastAvatarSyncDate = Date()
                }
            }
        } else {
            print("\n📦 使用本地缓存:")
            loadAvatarFromCache()
        }
    }
    
    private func saveAvatarToCache(_ imageData: Data) {
        print("\n💾 保存头像到本地缓存:")
        print("  - 数据大小: \(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file))")
        
        cachedAvatarData = imageData
        print("✅ 头像成功保存到缓存")
    }
    
    private func loadAvatarFromCache() {
        print("\n📂 从本地缓存加载头像:")
        print("  - 缓存大小: \(ByteCountFormatter.string(fromByteCount: Int64(cachedAvatarData.count), countStyle: .file))")
        
        if !cachedAvatarData.isEmpty {
            if let image = UIImage(data: cachedAvatarData) {
                self.cachedUIImage = image  // 使用 cachedUIImage 而不是 avatarImage
                print("✅ 成功从缓存加载头像")
            }
        } else {
            print("⚠️ 缓存中没有头像数据")
        }
    }
    
    private func updateAvatar(with image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.5) else { return }
        print("\n🔄 开始更新头像...")
        
        // 1. 先更新本地显示和缓存
        selectedImage = image  // 使用 selectedImage 而不是 avatarImage
        saveAvatarToCache(imageData)
        
        // 2. 然后更新到数据库
        let base64String = imageData.base64EncodedString()
        
        let db = Firestore.firestore()
        db.collection("users").document(userId).updateData([
            "avatar_base64": base64String,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("❌ 头像更新失败: \(error)")
                return
            }
            print("✅ 头像更新成功")
            self.lastAvatarSyncDate = Date()
        }
    }
    
    private func loadUserInfo() {
        print("\n📱 当前用户信息:")
        print("  - 用户ID: \(userId)")
        print("  - 用户名: \(userName)")
    }
}

struct AddFriendView: View {
    @Environment(\.dismiss) var dismiss
    @State private var username = ""
    @State private var isSearching = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack {
                TextField("输入用户名", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                Button("搜索并添加") {
                    searchUser()
                }
                .disabled(username.isEmpty || isSearching)
            }
            .navigationTitle("添加好友")
            .navigationBarItems(trailing: Button("取消") {
                dismiss()
            })
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func searchUser() {
        // 实现搜索用户逻辑
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
} 