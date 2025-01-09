import SwiftUI
import FirebaseFirestore

struct FriendRequestsView: View {
    @State private var requests: [FriendRequest] = []
    @State private var isLoading = false
    @AppStorage("userId") private var userId: String = ""
    
    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if requests.isEmpty {
                Text("暂无好友请求")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(requests) { request in
                    RequestCard(request: request, onAccept: {
                        handleRequest(request, accept: true)
                    }, onReject: {
                        handleRequest(request, accept: false)
                    })
                }
            }
        }
        .navigationTitle("好友请求")
        .onAppear {
            loadRequests()
        }
        .refreshable {
            loadRequests()
        }
    }
    
    private func loadRequests() {
        print("\n========== 加载好友请求 ==========")
        print("当前用户ID: \(userId)")
        
        isLoading = true
        let db = Firestore.firestore()
        
        // 创建两个查询：一个查询收到的请求，一个查询发送的请求
        let receivedQuery = db.collection("friendRequests")
            .whereField("toUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: FriendRequest.RequestStatus.pending.rawValue)
        
        let sentQuery = db.collection("friendRequests")
            .whereField("fromUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: FriendRequest.RequestStatus.pending.rawValue)
        
        print("查询条件:")
        print("- 接收的请求: toUserId = \(userId)")
        print("- 发送的请求: fromUserId = \(userId)")
        print("- status: pending")
        
        // 使用 DispatchGroup 来处理两个异步查询
        let group = DispatchGroup()
        var allRequests: [FriendRequest] = []
        
        // 查询接收的请求
        group.enter()
        receivedQuery.getDocuments(source: .default) { snapshot, error in
            defer { group.leave() }
            
            if let error = error {
                print("❌ 加载接收的请求失败: \(error.localizedDescription)")
                return
            }
            
            print("\n📝 接收的请求:")
            print("找到数量: \(snapshot?.documents.count ?? 0)")
            
            if let requests = snapshot?.documents.compactMap({ doc -> FriendRequest? in
                try? doc.data(as: FriendRequest.self)
            }) {
                allRequests.append(contentsOf: requests)
            }
        }
        
        // 查询发送的请求
        group.enter()
        sentQuery.getDocuments(source: .default) { snapshot, error in
            defer { group.leave() }
            
            if let error = error {
                print("❌ 加载发送的请求失败: \(error.localizedDescription)")
                return
            }
            
            print("\n📝 发送的请求:")
            print("找到数量: \(snapshot?.documents.count ?? 0)")
            
            if let requests = snapshot?.documents.compactMap({ doc -> FriendRequest? in
                try? doc.data(as: FriendRequest.self)
            }) {
                allRequests.append(contentsOf: requests)
            }
        }
        
        // 当所有查询完成时
        group.notify(queue: .main) {
            isLoading = false
            requests = allRequests.sorted { $0.timestamp > $1.timestamp }
            
            print("\n✅ 最终加载结果:")
            print("- 总请求数量: \(requests.count)")
            requests.forEach { request in
                let type = request.fromUserId == userId ? "发送" : "接收"
                print("- [\(type)] 请求ID: \(request.id), \(type)给: \(request.fromUsername)")
            }
        }
        
        print("========== 开始加载请求 ==========\n")
    }
    
    private func handleRequest(_ request: FriendRequest, accept: Bool) {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // 1. 更新请求状态
        let requestRef = db.collection("friendRequests").document(request.id)
        batch.updateData([
            "status": accept ? FriendRequest.RequestStatus.accepted.rawValue : FriendRequest.RequestStatus.rejected.rawValue
        ], forDocument: requestRef)
        
        if accept {
            // 2. 如果接受，添加到双方的好友列表
            let currentUserRef = db.collection("users").document(userId)
            let otherUserRef = db.collection("users").document(request.fromUserId)
            
            batch.updateData([
                "friendIds": FieldValue.arrayUnion([request.fromUserId])
            ], forDocument: currentUserRef)
            
            batch.updateData([
                "friendIds": FieldValue.arrayUnion([userId])
            ], forDocument: otherUserRef)
        }
        
        // 3. 提交批量更新
        batch.commit { error in
            if error == nil {
                // 4. 更新本地状态
                requests.removeAll { $0.id == request.id }
            }
        }
    }
}

struct RequestCard: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onReject: () -> Void
    @AppStorage("userId") private var userId: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if request.fromUserId == userId {
                    Text("发送给: \(request.fromUsername)")
                        .font(.headline)
                    Spacer()
                    Text("等待回应")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("来自: \(request.fromUsername)")
                        .font(.headline)
                }
            }
            
            Text("ID: \(request.fromUserId)")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(request.timestamp.formatted())
                .font(.caption)
                .foregroundColor(.gray)
            
            if request.fromUserId != userId {
                // 只有接收到的请求才显示接受/拒绝按钮
                HStack {
                    Spacer()
                    
                    Button(action: onReject) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                    }
                    
                    Button(action: onAccept) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}