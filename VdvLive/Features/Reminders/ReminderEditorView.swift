import SwiftUI

/// Adds a notification by choosing its stop, line, service, and then how it warns.
///
/// This is the only way a notification is set up. Everything before the last step is
/// a timetable fact - which lines call at the stop, which runs of that line do - so
/// the schedule the notification follows is the service's own.
struct ReminderEditorView: View {
    let viewModel: VehicleMapViewModel
    let onSave: (Reminder) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderCenter.self) private var center
    @State private var step: Step = .stop
    @State private var searchText = ""
    @State private var selectedStop: String?
    @State private var selectedLine: ReminderSetup.Line?
    @State private var selectedTimetable: LineTimetable?
    @State private var selectedService: ReminderSetup.Service?
    @State private var lineChoices: [ReminderSetup.Line] = []
    @State private var serviceChoices: [ReminderSetup.Service] = []
    @State private var isLoadingLines = false
    @State private var isLoadingServices = false
    @State private var errorMessage: String?
    @State private var leadMinutes = 10
    @State private var excludedWeekdays: Set<Int> = []

    private enum Step {
        case stop
        case line
        case service
        case customize
    }

    /// Stops to offer: everything when nothing is typed, otherwise the matcher's
    /// answers, which ignore accents and forgive a slipped letter.
    private var filteredStops: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return viewModel.allStopNames.filter { !viewModel.lines(atStopNamed: $0).isEmpty }
        }
        return viewModel.stopNames(matching: query)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .stop:
                    stopPicker
                case .line:
                    linePicker
                case .service:
                    servicePicker
                case .customize:
                    customization
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .stop ? "Cancel" : "Back") {
                        if step == .stop {
                            dismiss()
                        } else {
                            goBack()
                        }
                    }
                }
                if step == .customize {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(excludedWeekdays.count == 7)
                    }
                }
            }
            .alert("Unable to load timetables", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Step 1: the stop

    private var stopPicker: some View {
        List(filteredStops, id: \.self) { stop in
            Button {
                choose(stop: stop)
            } label: {
                HStack {
                    Text(stop)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $searchText, prompt: Text("Search stops"))
        .overlay {
            if !viewModel.timetables.isReady {
                ContentUnavailableView {
                    Label("Timetables not downloaded", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Download timetables in Settings before adding a notification.")
                }
            }
        }
        .disabled(!viewModel.timetables.isReady)
    }

    // MARK: - Step 2: the line

    private var linePicker: some View {
        List {
            if isLoadingLines {
                ProgressView("Loading timetable…")
            } else if lineChoices.isEmpty {
                ContentUnavailableView("No lines at this stop",
                                       systemImage: "bus",
                                       description: Text("No line is listed for this stop."))
            } else {
                ForEach(lineChoices) { line in
                    Button {
                        Task { await choose(line: line) }
                    } label: {
                        row(title: line.displayNumber,
                            caption: line.routeName.isEmpty ? nil : line.routeName)
                    }
                    .disabled(isLoadingServices)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Step 3: the service

    private var servicePicker: some View {
        List {
            if isLoadingServices {
                ProgressView("Reading services…")
            } else if serviceChoices.isEmpty {
                ContentUnavailableView("No services at this stop",
                                       systemImage: "bus",
                                       description: Text("This line has no timed service calling at the selected stop."))
            } else {
                ForEach(serviceChoices) { service in
                    Button {
                        choose(service: service)
                    } label: {
                        row(title: String(format: String(localized: "service %@"), service.serviceNumber),
                            detail: directionText(service),
                            caption: serviceCaption(service))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Step 4: how it warns

    private var customization: some View {
        Form {
            if let selectedStop, let selectedLine, let selectedService {
                Section {
                    LabeledContent("Stop", value: displayName(selectedStop))
                    LabeledContent("Line", value: selectedLine.displayNumber)
                    LabeledContent("Service") {
                        Text(String(format: String(localized: "service %@"), selectedService.serviceNumber))
                    }
                    LabeledContent("Direction", value: directionText(selectedService))
                }

                // The schedule the notification will follow, so the lead and the
                // excluded days are chosen against something visible.
                Section {
                    LabeledContent("Departs") {
                        Text(selectedService.departure.text).monospacedDigit()
                    }
                    LabeledContent("Runs") {
                        Text(restrictionLabel(selectedService.days.restriction))
                    }
                    LabeledContent("Timetable until") {
                        Text(timetableEndText)
                    }
                    LabeledContent("Next notification") {
                        Text(nextNotificationText)
                            .foregroundStyle(nextNotification == nil ? Color.secondary : Color.primary)
                    }
                } header: {
                    Text("Schedule")
                }

                Section {
                    Picker("Notify me", selection: $leadMinutes) {
                        ForEach(Reminder.leadOptions, id: \.self) { minutes in
                            Text(leadLabel(minutes)).tag(minutes)
                        }
                    }
                } header: {
                    Text("How far ahead")
                }

                Section {
                    ForEach(1...7, id: \.self) { weekday in
                        Toggle(isOn: binding(for: weekday)) {
                            Text(Self.weekdayName(weekday))
                        }
                    }
                } header: {
                    Text("Exclude days")
                } footer: {
                    Text("A day the service does not run on, or a public holiday, is left out on its own.")
                }
            }
        }
    }

    // MARK: - Chrome

    private func row(title: String, detail: String? = nil, caption: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold).monospacedDigit())
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var title: String {
        switch step {
        case .stop: String(localized: "Select stop")
        case .line: String(localized: "Select line")
        case .service: String(localized: "Select service")
        case .customize: String(localized: "Customize")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Choosing

    private func choose(stop: String) {
        guard viewModel.timetables.isReady else { return }
        selectedStop = stop
        selectedLine = nil
        selectedService = nil
        lineChoices = []
        step = .line
        Task { await loadLines(at: stop) }
    }

    private func loadLines(at stop: String) async {
        isLoadingLines = true
        defer { isLoadingLines = false }

        var loaded: [LineTimetable] = []
        for lineNumber in viewModel.lines(atStopNamed: stop) {
            if let timetable = try? await viewModel.timetables.timetable(forLine: lineNumber) {
                loaded.append(timetable)
            }
        }
        lineChoices = ReminderSetup.lines(in: loaded, atStopNamed: stop)
    }

    private func choose(line: ReminderSetup.Line) async {
        selectedLine = line
        selectedService = nil
        serviceChoices = []
        isLoadingServices = true
        defer { isLoadingServices = false }

        do {
            guard let timetable = try await viewModel.timetables.timetable(forLine: line.lineNumber) else {
                errorMessage = String(localized: "No timetable is available for this line.")
                return
            }
            selectedTimetable = timetable
            serviceChoices = ReminderSetup.services(in: timetable, atStopNamed: line.stopName)
            step = .service
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func choose(service: ReminderSetup.Service) {
        selectedService = service
        let existing = existingReminder(for: service)
        leadMinutes = existing?.leadMinutes ?? 10
        excludedWeekdays = existing?.excludedWeekdays ?? []
        step = .customize
    }

    private func existingReminder(for service: ReminderSetup.Service) -> Reminder? {
        guard let selectedLine else { return nil }
        return center.reminder(forLine: selectedLine.lineNumber,
                               serviceNumber: service.serviceNumber,
                               stopName: service.stopName)
    }

    private func save() {
        guard let selectedLine, let selectedService else { return }
        let existing = existingReminder(for: selectedService)
        onSave(Reminder(id: existing?.id ?? UUID(),
                        lineNumber: selectedLine.lineNumber,
                        serviceNumber: selectedService.serviceNumber,
                        stopName: selectedService.stopName,
                        leadMinutes: leadMinutes,
                        excludedWeekdays: excludedWeekdays))
        dismiss()
    }

    private func goBack() {
        switch step {
        case .stop:
            dismiss()
        case .line:
            step = .stop
        case .service:
            step = .line
        case .customize:
            step = .service
        }
    }

    // MARK: - Words

    /// The departure and the days, as one line: what the service is, in terms a
    /// printed timetable also uses.
    private func serviceCaption(_ service: ReminderSetup.Service) -> String {
        "\(service.departure.text) · \(restrictionLabel(service.days.restriction))"
    }

    /// Where the run goes, which is what tells two directions of one line apart.
    private func directionText(_ service: ReminderSetup.Service) -> String {
        String(format: String(localized: "%@ – %@"),
               displayName(service.origin),
               displayName(service.destination))
    }

    /// A timetable stop name with its comma spaced the way the rest of the app shows
    /// it: `Zašovice,Nová Brtnice` reads as `Zašovice, Nová Brtnice`.
    private func displayName(_ stopName: String) -> String {
        stopName.replacingOccurrences(of: ",", with: ", ")
    }

    /// How the archive's restriction is named: "working days", "weekends", "Sundays",
    /// or the days themselves when it is something else.
    private func restrictionLabel(_ restriction: ReminderSetup.Restriction) -> String {
        switch restriction {
        case .everyDay:
            return String(localized: "every day")
        case .workingDays:
            return String(localized: "working days")
        case .weekends:
            return String(localized: "weekends")
        case .sundays:
            return String(localized: "Sundays")
        case .sundaysAndHolidays:
            return String(localized: "Sundays and public holidays")
        case .chosenDays(let days):
            return ListFormatter.localizedString(byJoining: days.sorted().map(Self.weekdayName))
        }
    }

    /// The last day the timetable is published for, or the next change of timetables
    /// when the archive left the end open.
    private var timetableEndText: String {
        guard let end = selectedTimetable?.validity.compactMap(\.to).min() else {
            return String(localized: "Until the next timetable change")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ReminderSchedule.timeZone
        let parts = end.components
        guard let date = calendar.date(from: DateComponents(year: parts.year,
                                                            month: parts.month,
                                                            day: parts.day)) else {
            return String(localized: "Until the next timetable change")
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// The first moment the notification would arrive with the choices on screen.
    private var nextNotification: Date? {
        guard let timetable = selectedTimetable,
              let line = selectedLine,
              let service = selectedService else { return nil }
        let reminder = Reminder(lineNumber: line.lineNumber,
                                serviceNumber: service.serviceNumber,
                                stopName: service.stopName,
                                leadMinutes: leadMinutes,
                                excludedWeekdays: excludedWeekdays)
        return ReminderSchedule.occurrences(for: reminder, in: timetable, now: Date()).first?.fireAt
    }

    private var nextNotificationText: String {
        guard let nextNotification else { return String(localized: "Not on these days") }
        return Self.fireDateFormatter.string(from: nextNotification)
    }

    /// A fire time is a timetable moment, so it is shown in the timetables' own zone
    /// whatever the phone is set to.
    private static let fireDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = ReminderSchedule.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func leadLabel(_ minutes: Int) -> String {
        String(format: String(localized: "%lld min before"), minutes)
    }

    private func binding(for weekday: Int) -> Binding<Bool> {
        Binding(
            get: { excludedWeekdays.contains(weekday) },
            set: { isExcluded in
                if isExcluded {
                    excludedWeekdays.insert(weekday)
                } else {
                    excludedWeekdays.remove(weekday)
                }
            }
        )
    }

    /// Monday first, matching the archive's weekday numbering.
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
