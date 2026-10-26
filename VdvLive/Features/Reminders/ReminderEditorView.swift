import SwiftUI

/// The screen that makes a reminder: which run, which stop, how long before, and
/// which days the user actually wants it.
///
/// Everything here is a choice about *when a notification arrives*, not about what
/// the bus does - the timetable decides that, and the screen says when the timetable
/// stops.
struct ReminderEditorView: View {
    let lineNumber: String
    let serviceNumber: String
    let stopName: String
    /// The time this run leaves the stop, when the timetable could place it.
    let departureText: String?
    /// The last day the timetable is published for, as text.
    let lastDayText: String?
    /// The reminder already stored for this run and stop, if there is one.
    var existing: Reminder?

    let onSave: (Reminder) -> Void
    let onDelete: (Reminder) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var leadMinutes: Int
    @State private var excludedWeekdays: Set<Int>

    init(lineNumber: String,
         serviceNumber: String,
         stopName: String,
         departureText: String?,
         lastDayText: String?,
         existing: Reminder?,
         onSave: @escaping (Reminder) -> Void,
         onDelete: @escaping (Reminder) -> Void) {
        self.lineNumber = lineNumber
        self.serviceNumber = serviceNumber
        self.stopName = stopName
        self.departureText = departureText
        self.lastDayText = lastDayText
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete
        _leadMinutes = State(initialValue: existing?.leadMinutes ?? 10)
        _excludedWeekdays = State(initialValue: existing?.excludedWeekdays ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Line") {
                        Text(LineCode(raw: lineNumber).number)
                    }
                    LabeledContent("Service") {
                        Text(serviceNumber)
                    }
                    LabeledContent("Stop") {
                        Text(stopName.replacingOccurrences(of: ",", with: ", "))
                    }
                    if let departureText {
                        LabeledContent("Departs") {
                            Text(departureText).monospacedDigit()
                        }
                    }
                } footer: {
                    if let lastDayText {
                        Text(String(format: String(localized: "The timetable is published until %@."),
                                    lastDayText))
                    }
                }

                Section {
                    Picker("Warn me", selection: $leadMinutes) {
                        ForEach(leadOptions, id: \.self) { minutes in
                            Text(leadLabel(minutes)).tag(minutes)
                        }
                    }
                } footer: {
                    Text("The warning is about the timetable's own time. A late bus is not waited for: the notification arrives when the timetable says it should, and the app shows the live delay next time it is opened.")
                }

                Section {
                    ForEach(1...7, id: \.self) { weekday in
                        Toggle(isOn: binding(for: weekday)) {
                            Text(Self.weekdayName(weekday))
                        }
                    }
                } header: {
                    Text("Days")
                } footer: {
                    Text("Turn off a day you do not travel. A day the service does not run on, or a public holiday, is left out on its own.")
                }

                if let existing {
                    Section {
                        Button("Delete reminder", role: .destructive) {
                            onDelete(existing)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New reminder" : "Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Reminder(id: existing?.id ?? UUID(),
                                        lineNumber: lineNumber,
                                        serviceNumber: serviceNumber,
                                        stopName: stopName,
                                        leadMinutes: leadMinutes,
                                        excludedWeekdays: excludedWeekdays))
                        dismiss()
                    }
                    .disabled(excludedWeekdays.count == 7)
                }
            }
        }
    }

    private var leadOptions: [Int] { Reminder.leadOptions }

    private func leadLabel(_ minutes: Int) -> String {
        minutes == 0
            ? String(localized: "At departure")
            : String(format: String(localized: "%lld min before"), minutes)
    }

    private func binding(for weekday: Int) -> Binding<Bool> {
        Binding(
            get: { !excludedWeekdays.contains(weekday) },
            set: { isOn in
                if isOn {
                    excludedWeekdays.remove(weekday)
                } else {
                    excludedWeekdays.insert(weekday)
                }
            }
        )
    }

    /// Monday first, whatever the device's week starts on: the archive numbers days
    /// that way and so does the exclusion.
    private static let weekdayNames: [String] = {
        let formatter = DateFormatter()
        formatter.locale = .current
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] }
        return Array(symbols.dropFirst()) + [symbols[0]]
    }()

    private static func weekdayName(_ weekday: Int) -> String {
        guard weekdayNames.indices.contains(weekday - 1) else { return "" }
        return weekdayNames[weekday - 1]
    }
}
