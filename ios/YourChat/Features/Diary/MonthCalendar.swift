import SwiftUI

/// Month grid with a dot under every day that has an entry — filled for two or
/// more, hollow for one, matching the reference screen.
struct MonthCalendar: View {
    @Environment(ThemeStore.self) private var theme

    @Binding var month: Date
    let marks: [String: Int]

    private let calendar = Calendar.current
    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(spacing: 10) {
            header

            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryOnBackground)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day { cell(day) } else { Color.clear.frame(height: 34) }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
            }
            Spacer()
            Text(title)
                .font(.display(15, weight: .medium))
                .foregroundStyle(theme.onBackground)
            Spacer()
            Button { step(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.secondaryOnBackground)
    }

    private var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM yyyy"
        return f.string(from: month)
    }

    private func step(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.smooth(duration: 0.25)) { month = next }
    }

    /// Leading nils pad the grid so the 1st lands under the right weekday.
    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let leading = calendar.component(.weekday, from: first) - 1
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30

        return Array(repeating: nil, count: leading) + (0..<count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: first)
        }
    }

    private func cell(_ day: Date) -> some View {
        let key = DateOnly.string(from: day)
        let count = marks[key] ?? 0
        let isToday = calendar.isDateInToday(day)

        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 13))
                .foregroundStyle(theme.onBackground.opacity(isToday ? 1 : 0.75))
                .frame(width: 26, height: 26)
                .background {
                    if isToday {
                        Circle().strokeBorder(theme.onBackground.opacity(0.5), lineWidth: 1)
                    }
                }

            Group {
                if count >= 2 {
                    Circle().fill(theme.onBackground.opacity(0.75))
                } else if count == 1 {
                    Circle().strokeBorder(theme.onBackground.opacity(0.55), lineWidth: 1)
                } else {
                    Color.clear
                }
            }
            .frame(width: 4, height: 4)
        }
        .frame(height: 34)
    }
}
