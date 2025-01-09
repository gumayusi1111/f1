import SwiftUI
import FirebaseFirestore

struct FriendListView: View {
    @State private var friends: [User] = []
    @State private var isLoading = false
    @State private var selectedFriend: User? = nil
    @AppStorage("userId") private var userId: String = ""
    
    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if friends.isEmpty {
                Text("暂无好友")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(friends) { friend in
                    HStack {
                        // 头像
                        if let avatarData = Data(base64Encoded: friend.avatar_base64 ?? ""),
                           let uiImage = UIImage(data: avatarData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                                .onTapGesture {
                                    showFriendDetails(friend)
                                }
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.gray)
                                .onTapGesture {
                                    showFriendDetails(friend)
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(friend.username)
                                .font(.headline)
                            
                            Text("ID: \(friend.id)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .navigationTitle("好友列表")
        .sheet(item: $selectedFriend) { friend in
            NavigationView {
                FriendDetailView(friend: friend)
            }
        }
        .onAppear {
            loadFriends()
        }
        .refreshable {
            loadFriends()
        }
    }
    
    private func loadFriends() {
        print("\n========== 加载好友列表 ==========")
        print("当前用户ID: \(userId)")
        
        isLoading = true
        let db = Firestore.firestore()
        
        db.collection("users").document(userId).getDocument { snapshot, error in
            isLoading = false
            
            if let error = error {
                print("❌ 加载好友列表失败: \(error.localizedDescription)")
                return
            }
            
            if let data = snapshot?.data(),
               let friendIds = data["friendIds"] as? [String] {
                loadFriendDetails(friendIds)
            }
        }
    }
    
    private func loadFriendDetails(_ friendIds: [String]) {
        print("\n开始加载好友详细信息...")
        print("好友ID列表: \(friendIds)")
        
        let db = Firestore.firestore()
        let group = DispatchGroup()
        var loadedFriends: [User] = []
        
        for friendId in friendIds {
            group.enter()
            print("正在加载好友ID: \(friendId)")
            
            db.collection("users").document(friendId).getDocument { snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    print("❌ 加载好友信息失败: \(error.localizedDescription)")
                    return
                }
                
                do {
                    if var friend = try snapshot?.data(as: User.self) {
                        friend.id = snapshot?.documentID ?? ""  // 确保设置正确的文档 ID
                        print("✅ 成功加载好友: \(friend.username), ID: \(friend.id)")
                        loadedFriends.append(friend)
                    } else {
                        print("❌ 无法解码好友数据")
                    }
                } catch {
                    print("❌ 解码失败: \(error.localizedDescription)")
                    
                    // 尝试手动创建用户对象
                    if let data = snapshot?.data(),
                       let name = data["name"] as? String {
                        let friend = User(
                            id: snapshot?.documentID ?? "",
                            username: name,
                            avatar_base64: data["avatar_base64"] as? String,
                            onlineStatus: .offline,
                            lastStatusUpdate: (data["lastStatusUpdate"] as? Timestamp)?.dateValue(),
                            friendIds: data["friendIds"] as? [String] ?? []
                        )
                        print("✅ 手动创建好友: \(friend.username), ID: \(friend.id)")
                        loadedFriends.append(friend)
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            friends = loadedFriends
            print("\n最终加载结果:")
            print("- 成功加载好友数量: \(friends.count)")
            friends.forEach { friend in
                print("- 好友: \(friend.username), ID: \(friend.id)")
            }
        }
    }
    
    private func showFriendDetails(_ friend: User) {
        selectedFriend = friend
    }
} 