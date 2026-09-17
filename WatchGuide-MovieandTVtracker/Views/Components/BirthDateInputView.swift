import SwiftUI

struct BirthDateInputView: View {
    @Binding var date: Date

    var body: some View {
        #if os(tvOS)
        TVBirthDatePicker(date: $date)
        #else
        DatePicker(
            "Date of Birth",
            selection: $date,
            in: ...Date(),
            displayedComponents: .date
        )
        #if os(macOS)
        .datePickerStyle(.graphical)
        #else
        .datePickerStyle(.wheel)
        #endif
        .labelsHidden()
        #endif
    }
}

#if os(tvOS)
private struct TVBirthDatePicker: View {
    @Binding var date: Date

    private let calendar = Calendar.current

    private var years: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        return Array((currentYear - 120)...currentYear).reversed()
    }

    private var selectedYear: Binding<Int> {
        Binding(
            get: { calendar.component(.year, from: date) },
            set: { updateDate(year: $0) }
        )
    }

    private var selectedMonth: Binding<Int> {
        Binding(
            get: { calendar.component(.month, from: date) },
            set: { updateDate(month: $0) }
        )
    }

    private var selectedDay: Binding<Int> {
        Binding(
            get: { calendar.component(.day, from: date) },
            set: { updateDate(day: $0) }
        )
    }

    private var days: [Int] {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? date
        let dayRange = calendar.range(of: .day, in: .month, for: startOfMonth) ?? 1..<32
        return Array(dayRange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Month", selection: selectedMonth) {
                ForEach(1...12, id: \.self) { month in
                    Text(calendar.monthSymbols[month - 1]).tag(month)
                }
            }

            Picker("Day", selection: selectedDay) {
                ForEach(days, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }

            Picker("Year", selection: selectedYear) {
                ForEach(years, id: \.self) { year in
                    Text("\(year)").tag(year)
                }
            }
        }
    }

    private func updateDate(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        let currentYear = calendar.component(.year, from: date)
        let currentMonth = calendar.component(.month, from: date)
        let currentDay = calendar.component(.day, from: date)

        let nextYear = year ?? currentYear
        let nextMonth = month ?? currentMonth
        let nextDayBase = day ?? currentDay

        let startOfMonth = calendar.date(from: DateComponents(year: nextYear, month: nextMonth, day: 1)) ?? date
        let maxDay = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 31
        let nextDay = min(nextDayBase, maxDay)

        let components = DateComponents(
            year: nextYear,
            month: nextMonth,
            day: nextDay,
            hour: 12
        )

        if let updatedDate = calendar.date(from: components) {
            date = min(updatedDate, Date())
        }
    }
}
#endif
