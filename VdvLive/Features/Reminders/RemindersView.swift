import SwiftUI

/// The reminders the user has made, and the two things that stop them arriving:
/// a denied permission and a timetable that is not on the device.
///
/// Reached from Settings, because a reminder is set once and then forgotten about -
/// which is the point of it.
struct RemindersView: View {
    let viewModel: VehicleMapViewModel

    @Environment(ReminderCenter.self) private var center
    @State private var isAddingReminder = false

    var body: some View {
        List {
            if center.isDenied {
                Section {
                    Label("Notifications are turned off for this app, so no reminder can arrive. Turn them on in the system settings.",
                          systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !center.missingTimetableLines.isEmpty {
                Section {
                    ForEach(center.missingTimetableLines.sorted(), id: \.self) { line in
                        Label(String(format: String(localized: "Line %@ has no timetable on this device, so its reminders cannot be scheduled."),
                                    LineCode(raw: line).number),
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Missing timetables")
                }
            }

            Section {
                if center.reminders.isEmpty {
                    Text("Tap + to add a notification.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(center.reminders) { reminder in
                        row(reminder)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await center.remove(reminder) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            } footer: {
                Text("Reminders are worked out from the downloaded timetables, so they follow the service's own days: no weekends on a school run, no public holidays, and nothing after the timetable ends.")
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingReminder = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Add notification"))
            }
        }
        .sheet(isPresented: $isAddingReminder) {
            ReminderEditorView(viewModel: viewModel) { reminder in
                Task {
                    await center.requestPermissionIfNeeded()
                    await center.save(reminder)
                }
            }
        }
        .task { await center.scheduleAll() }
    }

    private func row(_ reminder: Reminder) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(reminder.displayLineNumber)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Text(String(format: String(localized: "service %@"), reminder.serviceNumber))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(leadText(reminder.leadMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(reminder.stopName.replacingOccurrences(of: ",", with: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func leadText(_ minutes: Int) -> String {
        minutes == 0
            ? String(localized: "At departure")
            : String(format: String(localized: "%lld min before"), minutes)
    }
}
