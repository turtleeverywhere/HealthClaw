import SwiftUI

// MARK: - Sparkline Chart

struct SparklineView: View {
    let data: [Double]
    var color: Color = .blue
    var showDot: Bool = true
    var showFill: Bool = true
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            if data.count >= 2 {
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = max(maxVal - minVal, 0.001)
                let pad: CGFloat = 6
                let w = geo.size.width - pad * 2
                let h = geo.size.height - pad * 2

                let points = data.enumerated().map { i, val in
                    CGPoint(
                        x: pad + w * CGFloat(i) / CGFloat(data.count - 1),
                        y: pad + h * (1 - CGFloat((val - minVal) / range))
                    )
                }

                // Gradient fill
                if showFill, let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: geo.size.height))
                        path.addLine(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                // Line
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                // End dot
                if showDot, let last = points.last {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .position(last)
                }
            }
        }
    }
}

// MARK: - Circular Progress Gauge

struct CircularGaugeView: View {
    let value: Double // 0-100
    let color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(value / 100, 1.0))
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.6), color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * min(value / 100, 1.0))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(Int(value))")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text("/ 100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Semi-Circular Gauge (for body fat, RHR)

struct SemiGaugeView: View {
    let value: Double
    let minValue: Double
    let maxValue: Double
    var colors: [Color] = [.blue, .cyan, .green, .yellow, .orange]

    private var normalized: Double {
        max(0, min(1, (value - minValue) / max(maxValue - minValue, 0.001)))
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.88)
            let radius = min(geo.size.width / 2, geo.size.height * 0.85) * 0.85

            // Background arc
            Path { path in
                path.addArc(center: center, radius: radius,
                            startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            }
            .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 8, lineCap: .round))

            // Colored arc
            Path { path in
                path.addArc(center: center, radius: radius,
                            startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            }
            .stroke(
                AngularGradient(
                    colors: colors,
                    center: UnitPoint(x: 0.5, y: 0.88),
                    startAngle: .degrees(180),
                    endAngle: .degrees(360)
                ),
                style: StrokeStyle(lineWidth: 8, lineCap: .round)
            )

            // Tick marks
            ForEach(0..<21, id: \.self) { i in
                let tickAngle = Angle.degrees(180 + Double(i) * 180.0 / 20.0)
                let innerR = radius - 14
                let outerR = radius - 6
                Path { path in
                    path.move(to: CGPoint(
                        x: center.x + innerR * cos(CGFloat(tickAngle.radians)),
                        y: center.y + innerR * sin(CGFloat(tickAngle.radians))
                    ))
                    path.addLine(to: CGPoint(
                        x: center.x + outerR * cos(CGFloat(tickAngle.radians)),
                        y: center.y + outerR * sin(CGFloat(tickAngle.radians))
                    ))
                }
                .stroke(Color.white.opacity(i % 5 == 0 ? 0.25 : 0.1), lineWidth: 1)
            }

            // Indicator dot
            let angle = Angle.degrees(180 + normalized * 180)
            Circle()
                .fill(Color.white)
                .shadow(color: .white.opacity(0.4), radius: 3)
                .frame(width: 10, height: 10)
                .position(
                    x: center.x + radius * cos(CGFloat(angle.radians)),
                    y: center.y + radius * sin(CGFloat(angle.radians))
                )

            // Min/Max labels
            Text("\u{2212}")
                .font(.caption2.bold())
                .foregroundStyle(.blue)
                .position(x: center.x - radius - 12, y: center.y + 8)
            Text("+")
                .font(.caption2.bold())
                .foregroundStyle(.red)
                .position(x: center.x + radius + 12, y: center.y + 8)
        }
    }
}

// MARK: - Range Indicator (VO2 Max style)

struct RangeIndicatorView: View {
    let value: Double
    let ranges: [(min: Double, max: Double)]
    var activeColor: Color = .blue

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(ranges.enumerated().reversed()), id: \.offset) { _, range in
                GeometryReader { geo in
                    let isActive = value >= range.min && value < range.max
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isActive ? activeColor.opacity(0.5) : Color.white.opacity(0.06))

                        if isActive {
                            let fraction = (value - range.min) / max(range.max - range.min, 0.001)
                            Circle()
                                .fill(activeColor)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .frame(width: 14, height: 14)
                                .position(
                                    x: max(7, min(geo.size.width - 7, geo.size.width * CGFloat(fraction))),
                                    y: geo.size.height / 2
                                )
                        }
                    }
                }
                .frame(height: 14)
            }
        }
    }
}

// MARK: - Trend Label

struct TrendLabel: View {
    let data: [Double]

    private var trend: (symbol: String, text: String, color: Color) {
        guard data.count >= 2 else { return ("arrow.right", "No data", .gray) }
        let halfCount = max(data.count / 2, 1)
        let firstHalf = Array(data.prefix(halfCount))
        let secondHalf = Array(data.suffix(halfCount))
        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        let change = (secondAvg - firstAvg) / max(abs(firstAvg), 0.001)

        if change > 0.03 {
            return ("arrow.up.right", "Increasing", .green)
        } else if change < -0.03 {
            return ("arrow.down.right", "Decreasing", .orange)
        } else {
            return ("arrow.right", "Stabilizing", .blue)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.symbol)
                .font(.caption2)
            Text(trend.text)
                .font(.caption)
        }
        .foregroundStyle(trend.color)
    }
}

// MARK: - Sleep Stage Bar

struct SleepStageBar: View {
    let stages: [(stage: String, fraction: Double)]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(stageColor(stage.stage))
                        .frame(width: max(2, geo.size.width * stage.fraction))
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    func stageColor(_ stage: String) -> Color {
        switch stage {
        case "deep": return .indigo
        case "rem": return .cyan
        case "core": return .blue
        case "awake": return Color.gray.opacity(0.5)
        default: return .secondary
        }
    }
}
