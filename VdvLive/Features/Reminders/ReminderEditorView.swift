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

    private var filteredStops: [String] {
        let names = viewModel.allStopNames.filter { !viewModel.lines(atStopNamed: $0).isEmpty }
        guard !searchText.isEmpty else { return names }
        return names.filter { $0.localizedCaseInsensitiveContains(searchText) }
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
                    LabeledContent("Stop", value: selectedStop.replacingOccurrences(of: ",", with: ", "))
                    LabeledContent("Line", value: selectedLine.displayNumber)
                    LabeledContent("Service") {
                        Text(String(format: String(localized: "service %@"), selectedService.serviceNumber))
                    }
                    LabeledContent("Departs") {
                        Text(selectedService.departure.text).monospacedDigit()
                    }
                    LabeledContent("Runs") {
                        Text(daySummary(selectedService.days))
                    }
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

    private func row(title: String, caption: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold).monospacedDigit())
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

    private func serviceCaption(_ service: ReminderSetup.Service) -> String {
        "\(service.departure.text) · \(daySummary(service.days))"
    }

    private func daySummary(_ weekdays: ReminderSetup.Weekdays) -> String {
        let names = weekdays.days.sorted().map(Self.weekdayName)
        var summary: String
        if weekdays.isEveryDay {
            summary = String(localized: "Every day")
        } else if weekdays.days == Set(1...5) {
            summary = "\(names.first ?? "")–\(names.last ?? "")"
        } else {
            summary = ListFormatter.localizedString(byJoining: names)
        }
        if weekdays.includesHolidays {
            summary += " " + String(localized: "and public holidays")
        }
        return summary
    }

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
