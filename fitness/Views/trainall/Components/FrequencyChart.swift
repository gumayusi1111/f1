import SwiftUI
import Charts

// 主视图
struct FrequencyChart: View {
    let workouts: [WorkoutRecord]
    
    var body: some View {
        ChartContainer(data: WorkoutDataProcessor(workouts: workouts).processData())
    }
}

// 数据处理器
private struct WorkoutDataProcessor {
    let workouts: [WorkoutRecord]
    private let calendar = Calendar.current
    
    init(workouts: [WorkoutRecord]) {
        self.workouts = workouts
    }
    
    func processData() -> [ChartData] {
        let dates = generateDateRange()
        let counts = calculateWorkoutCounts()
        return createChartData(dates: dates, counts: counts)
    }
    
    private func generateDateRange() -> [Date] {
        let now = Date()
        let weekStart = calendar.date(byAdding: .day, value: -28, to: now)!
        let endDate = calendar.startOfDay(for: now)
        var currentDate = calendar.startOfDay(for: weekStart)
        
        var dates: [Date] = []
        while currentDate <= endDate {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate
        }
        return dates
    }
    
    private func calculateWorkoutCounts() -> [Date: Int] {
        Dictionary(grouping: workouts) { workout in
            calendar.startOfDay(for: workout.date)
        }.mapValues { $0.count }
    }
    
    private func createChartData(dates: [Date], counts: [Date: Int]) -> [ChartData] {
        dates.map { date in
            ChartData(date: date, count: counts[date] ?? 0)
        }
    }
}

// 图表容器
private struct ChartContainer: View {
    let data: [ChartData]
    private let calendar = Calendar.current
    
    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("日期", item.date),
                y: .value("次数", item.count)
            )
            .foregroundStyle(Color.blue.gradient)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    let day = calendar.component(.day, from: date)
                    if day % 5 == 0 {
                        AxisValueLabel {
                            VStack(alignment: .leading) {
                                Text("\(calendar.component(.month, from: date))月")
                                    .font(.caption2)
                                Text("\(day)日")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 200)
    }
}

// 图表数据模型
struct ChartData: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
} 