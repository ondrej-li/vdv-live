import SwiftUI

/// Adds a notification by choosing its stop, line, service, and notification rules.
struct ReminderEditorView: View {
    let viewModel: VehicleMapViewModel
    let onSave: (Reminder) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderCenter.self) private var center
    @State private var step: Step = .stop
    @State private var searchText = ""
    @State private var selectedStop: String?
    @State private var selectedLine: LineTimetable?
    @State private var selectedService: ServiceChoice?
    @State private var lineChoices: [String] = []
    @State private var serviceChoices: [ServiceChoice] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var leadMinutes = 10
    @State private var excludedWeekdays: Set<Int> = []

    private enum Step {
        case stop
        case line
        case service
        case customize
    }

    private struct ServiceChoice: Identifiable {
        let run: ScheduledRun
        let stopName: String
        var id: String { run.serviceNumber }
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
        .disabled(isLoading || !viewModel.timetables.isReady)
    }

    private var linePicker: some View {
        List {
            if isLoading {
                ProgressView("Loading timetable…")
            } else if lineChoices.isEmpty {
                ContentUnavailableView("No lines at this stop",
                                       systemImage: "bus",
                                       description: Text("No line is listed for this stop."))
            } else {
                ForEach(lineChoices, id: \.self) { lineNumber in
                    Button {
                        Task { await choose(lineNumber: lineNumber) }
                    } label: {
                        HStack {
                            Text(LineCode(raw: lineNumber).number)
                                .font(.body.weight(.semibold).monospacedDigit())
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .disabled(isLoading)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var servicePicker: some View {
        List(serviceChoices) { choice in
            Button {
                selectedService = choice
                leadMinutes = existingReminder(for: choice)?.leadMinutes ?? 10
                excludedWeekdays = existingReminder(for: choice)?.excludedWeekdays ?? []
                step = .customize
            } label: {
                HStack {
                    Text(String(format: String(localized: "service %@"), choice.run.serviceNumber))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if serviceChoices.isEmpty {
                ContentUnavailableView("No services at this stop",
                                       systemImage: "bus",
                                       description: Text("This line has no timed service calling at the selected stop."))
            }
        }
    }

    private var customization: some View {
        Form {
            if let selectedStop, let selectedLine, let selectedService {
                Section {
                    LabeledContent("Stop", value: selectedStop)
                    LabeledContent("Line", value: selectedLine.displayNumber)
                    LabeledContent("Service", value: selectedService.run.serviceNumber)
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
                }
            }
        }
    }

    private var title: String {
        switch step {
        case .stop: "Select stop"
        case .line: "Select line"
        case .service: "Select service"
        case .customize: "Customize"
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func choose(stop: String) {
        guard viewModel.timetables.isReady else { return }
        selectedStop = stop
        selectedLine = nil
        selectedService = nil
        lineChoices = viewModel.lines(atStopNamed: stop).sorted {
            LineCode(raw: $0).number.localizedStandardCompare(LineCode(raw: $1).number) == .orderedAscending
        }
        step = .line
    }

    private func choose(lineNumber: String) async {
        guard let selectedStop else { return }
        selectedLine = nil
        selectedService = nil
        isLoading = true
        defer { isLoading = false }
        do {
            guard let timetable = try await viewModel.timetables.timetable(forLine: lineNumber) else {
                errorMessage = String(localized: "No timetable is available for this line.")
                return
            }
            selectedLine = timetable
            serviceChoices = services(in: timetable, at: selectedStop)
            step = .service
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func services(in timetable: LineTimetable, at stopName: String) -> [ServiceChoice] {
        timetable.runs.compactMap { run in
            guard let call = run.call(matchingStopName: stopName), call.time != nil else { return nil }
            return ServiceChoice(run: run, stopName: call.stopName)
        }
        .sorted { $0.run.serviceNumber.compare($1.run.serviceNumber, options: .numeric) == .orderedAscending }
    }

    private func existingReminder(for choice: ServiceChoice) -> Reminder? {
        guard let selectedLine else { return nil }
        return center.reminder(forLine: selectedLine.lineNumber,
                               serviceNumber: choice.run.serviceNumber,
                               stopName: choice.stopName)
    }

    private func save() {
        guard let selectedLine, let selectedService else { return }
        let existing = existingReminder(for: selectedService)
        onSave(Reminder(id: existing?.id ?? UUID(),
                        lineNumber: selectedLine.lineNumber,
                        serviceNumber: selectedService.run.serviceNumber,
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

    private func leadLabel(_ minutes: Int) -> String {
        minutes == 0
            ? String(localized: "At departure")
            : String(format: String(localized: "%lld min before"), minutes)
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
