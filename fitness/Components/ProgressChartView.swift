import SwiftUI
import Charts

struct ExerciseProgressChart: View {
    let records: [ExerciseRecord]
    let unit: String
    @Environment(\.colorScheme) private var colorScheme
    
    // 限制显示最近10条记录，并按日期正序排列
    private var chartData: [ExerciseRecord] {
        Array(records.prefix(10)).reversed()
    }
    
    // 计算进步率
    private var progressRate: Double? {
        guard let firstValue = chartData.first?.value,
              let lastValue = chartData.last?.value else {
            return nil
        }
        return ((lastValue - firstValue) / firstValue) * 100
    }
    
    // 获取渐变色
    private var gradientColors: [Color] {
        colorScheme == .dark ? 
            [Color.blue.opacity(0.8), Color.blue.opacity(0.2)] :
            [Color.blue.opacity(0.3), Color.blue.opacity(0.05)]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题栏
            HStack(spacing: 12) {
                // 左侧标题
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("进步曲线")
                        .font(.system(size: 17, weight: .semibold))
                }
                
                Spacer()
                
                // 右侧进步率
                if let rate = progressRate {
                    HStack(spacing: 6) {
                        Image(systemName: rate >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                            .foregroundStyle(rate >= 0 ? .green : .red)
                            .font(.system(size: 16))
                        Text(String(format: "%.1f%%", abs(rate)))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(rate >= 0 ? .green : .red)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        (rate >= 0 ? Color.green : Color.red)
                            .opacity(0.1)
                            .cornerRadius(8)
                    )
                }
            }
            .padding(.horizontal)
            
            if records.isEmpty {
                // 空状态优化
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.gray.opacity(0.5))
                    Text("暂无数据")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                // 图表区域
                Chart(chartData) { record in
                    // 面积渐变
                    AreaMark(
                        x: .value("日期", record.date),
                        y: .value("数值", record.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // 连线
                    LineMark(
                        x: .value("日期", record.date),
                        y: .value("数值", record.value)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    // 数据点和PR标记组合
                    PointMark(
                        x: .value("日期", record.date),
                        y: .value("数值", record.value)
                    )
                    .foregroundStyle(record.isPR ? .yellow : .blue)
                    .symbol(record.isPR ? .diamond : .circle)
                    .symbolSize(record.isPR ? 120 : 60)
                    .annotation(position: .top) {
                        if record.isPR {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 14))
                                .shadow(color: .black.opacity(0.2), radius: 1)
                                .offset(y: -10)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.month().day()))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let value = value.as(Double.self) {
                                Text("\(value, specifier: "%.1f")\(unit)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 220)
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.06),
                    radius: 15,
                    x: 0,
                    y: 5
                )
        )
        .padding(.horizontal)
    }
} 