import SwiftUI
import Charts
import UIKit

/// One bar in the statistics weekday chart. `weekday` is the calendar
/// component (1 = Sunday … 7 = Saturday) so the SwiftUI chart can sort
/// deterministically even when the input is shuffled.
struct WeekdayBarPoint: Identifiable {
    let id = UUID()
    let label: String
    let amount: Double
    let weekday: Int
}

/// Apple-Charts bar chart for the statistics screen. Renders 7 bars
/// (Mon → Sun) with the money gradient when the value is non-zero, and a
/// muted overlay-only fill for empty days so the axis stays balanced.
///
/// Lives in its own file to keep `StatisticsViewController` under the
/// SwiftLint `type_body_length` ceiling — the SwiftUI body alone runs
/// 50+ lines once the axis configuration lands, and the VC otherwise
/// trips the 350-line type body limit.
struct WeekdayChartView: View {

    let bars: [WeekdayBarPoint]

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("День", bar.label),
                y: .value("Среднее", bar.amount)
            )
            .foregroundStyle(
                bar.amount > 0
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                Color(uiColor: AppColors.money400),
                                Color(uiColor: AppColors.money700)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    : AnyShapeStyle(Color(uiColor: AppColors.whiteOverlay06))
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel()
                    .font(.caption)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text("\(Int(amount))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYScale(domain: 0...(maxAmount * 1.2))
    }

    /// Y-axis cap. Falls back to 1 so an all-zero bar set still renders an
    /// axis with sane tick marks instead of collapsing to a 0...0 domain.
    private var maxAmount: Double {
        max(bars.map(\.amount).max() ?? 1, 1)
    }
}
