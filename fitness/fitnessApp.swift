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
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        // 设置通知代理
        UNUserNotificationCenter.current().delegate = self
        
        return true
    }
    
    // 实现通知代理方法
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 允许在前台显示通知
        completionHandler([.banner, .sound, .badge])
    }
}

@main
struct fitnessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            SplashView()
        }
    }
}
