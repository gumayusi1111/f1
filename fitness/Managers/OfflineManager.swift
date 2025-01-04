import Foundation
import FirebaseFirestore
import Combine

class OfflineManager: ObservableObject {
    @Published private(set) var pendingOperationsCount: Int = 0
    
    // 离线操作类型
    enum OperationType: String, Codable {
        case add
        case update
        case delete
    }
    
    // 离线操作模型
    struct PendingOperation: Codable, Identifiable {
        let id: String
        let type: OperationType
        let data: Data  // 编码后的 WeightRecord
        let timestamp: Date
        let retryCount: Int
    }
    
    // 存储键
    private let pendingOperationsKey = "pendingWeightOperations"
    
    // 获取待处理操作
    func getPendingOperations() -> [PendingOperation] {
        guard let data = UserDefaults.standard.data(forKey: pendingOperationsKey),
              let operations = try? JSONDecoder().decode([PendingOperation].self, from: data) else {
            return []
        }
        return operations
    }
    
    // 添加离线操作
    func addOperation(type: OperationType, record: WeightRecord) {
        var operations = getPendingOperations()
        
        if let recordData = try? JSONEncoder().encode(record) {
            let operation = PendingOperation(
                id: UUID().uuidString,
                type: type,
                data: recordData,
                timestamp: Date(),
                retryCount: 0
            )
            operations.append(operation)
            
            if let encoded = try? JSONEncoder().encode(operations) {
                UserDefaults.standard.set(encoded, forKey: pendingOperationsKey)
                DispatchQueue.main.async {
                    self.pendingOperationsCount = operations.count
                }
            }
        }
    }
    
    // 处理离线队列
    func processPendingOperations(completion: @escaping (Bool) -> Void) {
        let operations = getPendingOperations()
        guard !operations.isEmpty else {
            completion(true)
            return
        }
        
        // 处理每个操作
        let group = DispatchGroup()
        var success = true
        
        for operation in operations {
            group.enter()
            
            processOperation(operation) { result in
                if !result {
                    success = false
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(success)
        }
    }
    
    // 处理单个操作
    private func processOperation(_ operation: PendingOperation, completion: @escaping (Bool) -> Void) {
        guard let record = try? JSONDecoder().decode(WeightRecord.self, from: operation.data) else {
            completion(false)
            return
        }
        
        let db = Firestore.firestore()
        
        // 先检查是否存在冲突
        db.collection("users")
            .document(record.userId)
            .collection("weightRecords")
            .document(record.id)
            .getDocument { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let serverData = snapshot?.data(),
                   let serverRecord = try? self.decodeRecord(from: serverData) {
                    // 存在服务器记录，处理冲突
                    let finalRecord = self.handleConflict(
                        localRecord: record,
                        serverRecord: serverRecord
                    )
                    
                    // 根据冲突处理结果更新数据库
                    switch operation.type {
                    case .add, .update:
                        db.collection("users")
                            .document(record.userId)
                            .collection("weightRecords")
                            .document(record.id)
                            .setData([
                                "weight": finalRecord.weight,
                                "date": finalRecord.date,
                                "userId": finalRecord.userId
                            ]) { error in
                                print(error == nil ? "✅ 冲突解决并更新成功" : "❌ 冲突解决更新失败")
                                completion(error == nil)
                            }
                    case .delete:
                        // 如果是删除操作，直接执行删除
                        db.collection("users")
                            .document(record.userId)
                            .collection("weightRecords")
                            .document(record.id)
                            .delete { error in
                                completion(error == nil)
                            }
                    }
                } else {
                    // 无冲突，执行原始操作
                    switch operation.type {
                    case .add:
                        db.collection("users")
                            .document(record.userId)
                            .collection("weightRecords")
                            .document(record.id)
                            .setData([
                                "weight": record.weight,
                                "date": record.date,
                                "userId": record.userId
                            ]) { error in
                                completion(error == nil)
                            }
                        
                    case .update:
                        db.collection("users")
                            .document(record.userId)
                            .collection("weightRecords")
                            .document(record.id)
                            .updateData([
                                "weight": record.weight,
                                "date": record.date
                            ]) { error in
                                completion(error == nil)
                            }
                        
                    case .delete:
                        db.collection("users")
                            .document(record.userId)
                            .collection("weightRecords")
                            .document(record.id)
                            .delete { error in
                                completion(error == nil)
                            }
                    }
                }
            }
    }
    
    // 清除已处理的操作
    func clearProcessedOperations() {
        UserDefaults.standard.removeObject(forKey: pendingOperationsKey)
    }
    
    // 在 OfflineManager 中添加冲突处理
    private func handleConflict(localRecord: WeightRecord, serverRecord: WeightRecord) -> WeightRecord {
        // 如果服务器记录更新，使用服务器记录
        if serverRecord.date > localRecord.date {
            return serverRecord
        }
        // 否则保留本地记录
        return localRecord
    }
    
    private func decodeRecord(from data: [String: Any]) throws -> WeightRecord {
        guard let weight = data["weight"] as? Double,
              let userId = data["userId"] as? String,
              let date = (data["date"] as? Timestamp)?.dateValue(),
              let id = data["id"] as? String else {
            throw NSError(domain: "RecordDecoding", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid record data format"
            ])
        }
        
        return WeightRecord(
            id: id,
            userId: userId,
            weight: weight,
            date: date
        )
    }
} 