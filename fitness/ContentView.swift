//
//  ContentView.swift
//  fitness
//
//  Created by 文白 on 2025/1/2.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("userName") private var userName: String = ""
    
    var body: some View {
        TabView {
            // 日历主页
            CalendarView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("日历")
                }
            
            // 体重记录
            WeightView()
                .tabItem {
                    Image(systemName: "scalemass")
                    Text("体重")
                }
            
            // 极限记录
            MaxRecordsView()
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("极限")
                }
            
            // 训练跟踪
            TrainingView()
                .tabItem {
                    Image(systemName: "figure.run")
                    Text("训练")
                }
            
            // 个人中心
            ProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("我的")
                }
        }
    }
}

#Preview {
    ContentView()
}
