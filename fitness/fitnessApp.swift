//
//  fitnessApp.swift
//  fitness
//
//  Created by 文白 on 2025/1/2.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static var sharedDb: Firestore?
    private static var currentUserId: String?
    private static var isInitialized = false  // 添加初始化标志
    
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        // 只在首次启动时初始化 Firestore
        if !AppDelegate.isInitialized {
            print("📝 首次初始化 Firestore")
            
            // 创建 Firestore 实例
            let db = Firestore.firestore()
            
            // 配置设置
            let settings = FirestoreSettings()
            settings.cacheSettings = PersistentCacheSettings(
                sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited)
            )
            db.settings = settings
            
            AppDelegate.sharedDb = db
            AppDelegate.isInitialized = true
            print("✅ Firestore 初始化完成")
        }
        
        // 设置通知代理
        UNUserNotificationCenter.current().delegate = self
        
        print("✅ Firebase 初始化完成")
        return true
    }
    
    // 在用户登录成功后调用此方法初始化用户数据
    func initializeUserData(userId: String) {
        guard let db = AppDelegate.sharedDb else {
            print("❌ Firestore 未初始化")
            return
        }
        
        // 设置当前用户ID
        setCurrentUserId(userId)
        
        print("🔄 开始初始化用户数据: \(userId)")
        let userRef = db.collection("users").document(userId)
        
        userRef.getDocument { [weak self] snapshot, error in
            if let error = error {
                print("❌ 检查用户时出错: \(error)")
                return
            }
            
            print("📝 用户文档状态: \(snapshot?.exists == true ? "存在" : "不存在")")
            if snapshot?.exists != true {
                // 创建用户文档
                userRef.setData([
                    "name": "用户",
                    "createdAt": FieldValue.serverTimestamp(),
                    "settings": [
                        "waterIntakeGoal": 7,
                        "weightReminders": true
                    ]
                ]) { error in
                    if let error = error {
                        print("❌ 创建用户失败: \(error)")
                    } else {
                        print("✅ 用户创建成功")
                        self?.initializeWaterIntakeCollection(userId: userId)
                    }
                }
            }
        }
    }
    
    private func initializeWaterIntakeCollection(userId: String) {
        guard let db = AppDelegate.sharedDb else {
            print("❌ Firestore 未初始化")
            return
        }
        
        print("📝 开始初始化喝水记录")
        let waterIntakeRef = db.collection("users").document(userId).collection("waterIntake")
        
        // 创建今日记录
        let today = Calendar.current.startOfDay(for: Date())
        waterIntakeRef.document(today.ISO8601Format()).setData([
            "cups": 0,
            "goal": 7,
            "lastUpdated": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("❌ 创建喝水记录失败: \(error)")
            } else {
                print("✅ 喝水记录初始化成功")
            }
        }
    }
    
    // 实现通知代理方法
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 允许在前台显示通知
        completionHandler([.banner, .sound, .badge])
    }
    
    // 修改获取 Firestore 实例的方法
    func getFirestore() -> Firestore? {
        if !AppDelegate.isInitialized {
            print("❌ Firestore 未初始化")
            return nil
        }
        return AppDelegate.sharedDb
    }
    
    // 添加设置当前用户ID的方法
    func setCurrentUserId(_ userId: String?) {
        print("📝 设置当前用户ID: \(userId ?? "nil")")
        AppDelegate.currentUserId = userId
    }
    
    // 添加获取当前用户ID的方法
    func getCurrentUserId() -> String? {
        return AppDelegate.currentUserId
    }
    
    // 添加清理用户数据的方法
    func clearUserData() {
        print("🧹 清理用户数据")
        setCurrentUserId(nil)
    }
}

// 添加一个全局访问点
class AppDelegateManager {
    static var shared: AppDelegate?
}

@main
struct fitnessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("userId") private var userId: String = ""
    
    init() {
        // 保存 AppDelegate 实例
        AppDelegateManager.shared = delegate
    }
    
    var body: some Scene {
        WindowGroup {
            if userId.isEmpty {
                LoginView()
            } else {
                ContentView()
            }
        }
    }
}
