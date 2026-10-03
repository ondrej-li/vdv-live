import SwiftUI

/// What the app prefers: how often it refreshes, in which language, how the map
/// behaves, and everything about the user's own position.
struct PreferencesView: View {
    let settings: AppSettings
    let onSetAutoRefreshEnabled: (Bool) -> Void
    let onSetAutoRefreshInterval: (TimeInterval) -> Void
    let onSetLanguage: (AppLanguage) -> Void
    let onSetClusterRadius: (Double) -> Void
    let onSetShowsCurrentLocation: (Bool) -> Void
    let onSetFollowsCurrentLocation: (Bool) -> Void
    let onSetStartsAtCurrentLocation: (Bool) -> Void
    let onSetShowsStops: (Bool) -> Void
    let onClearSavedMapView: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Automatic refresh", isOn: autoRefreshEnabledBinding)

                Picker("Refresh interval", selection: autoRefreshIntervalBinding) {
                    ForEach(intervalOptions, id: \.self) { interval in
                        Text(Self.intervalLabel(interval)).tag(interval)
                    }
                }
                .disabled(!settings.autoRefreshEnabled)
            } header: {
                Text("Refresh")
            } footer: {
                Text(
                    String(
                        format: String(
                            localized: "The feed reports new positions every few seconds. Asking for them more often than every %lld s only costs battery."
                        ),
                        Int(AppSettings.minimumAutoRefreshInterval)
                    )
                )
            }

            Section {
                Picker("Language", selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Czech is the default. A language change takes effect the next time the app starts.")
            }

            Section {
                Picker("Group buses within", selection: clusterRadiusBinding) {
                    ForEach(radiusOptions, id: \.self) { radius in
                        Text(Self.radiusLabel(radius)).tag(radius)
                    }
                }
            } header: {
                Text("Vehicles")
            } footer: {
                Text("Buses closer together than this share one marker, which keeps a busy region readable when it is zoomed out. Off, every vehicle is drawn on its own.")
            }

            Section {
                Toggle("Show stops on the map", isOn: showsStopsBinding)
            } header: {
                Text("Stops")
            } footer: {
                Text("Stops are drawn as a flag once the map is zoomed in far enough to read them. The positions are matched from OpenStreetMap by name, so most of the region's stops are there and some are not.")
            }

            Section {
                Toggle("Show my position on the map", isOn: showsCurrentLocationBinding)
                Toggle("Follow my position", isOn: followsCurrentLocationBinding)
                Toggle("Open at my location", isOn: startsAtCurrentLocationBinding)

                if settings.savedMapView != nil {
                    Button("Clear saved view", role: .destructive, action: onClearSavedMapView)
                }
            } header: {
                Text("My location")
            } footer: {
                Text("The position is read on the device and never sent anywhere. The blue dot is the system's own; following keeps the map centred on it while you move, and the bookmark button remembers the view you are looking at instead.")
            }
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Offered intervals, plus the current one if it is not among them, so that
    /// a value written by another build still shows up in the picker.
    private var intervalOptions: [TimeInterval] {
        let selectable = AppSettings.selectableAutoRefreshIntervals
        guard !selectable.contains(settings.autoRefreshInterval) else { return selectable }
        return (selectable + [settings.autoRefreshInterval]).sorted()
    }

    /// Offered radii, plus whatever is stored when it is not among them, so that a
    /// value written by another build still shows up in the picker.
    private var radiusOptions: [Double] {
        let selectable = AppSettings.selectableClusterRadii
        guard !selectable.contains(settings.clusterRadiusMetres) else { return selectable }
        return (selectable + [settings.clusterRadiusMetres]).sorted()
    }

    private var autoRefreshEnabledBinding: Binding<Bool> {
        Binding(get: { settings.autoRefreshEnabled }, set: onSetAutoRefreshEnabled)
    }

    private var autoRefreshIntervalBinding: Binding<TimeInterval> {
        Binding(get: { settings.autoRefreshInterval }, set: onSetAutoRefreshInterval)
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { settings.language }, set: onSetLanguage)
    }

    private var clusterRadiusBinding: Binding<Double> {
        Binding(get: { settings.clusterRadiusMetres }, set: onSetClusterRadius)
    }

    private var showsCurrentLocationBinding: Binding<Bool> {
        Binding(get: { settings.showsCurrentLocation }, set: onSetShowsCurrentLocation)
    }

    private var followsCurrentLocationBinding: Binding<Bool> {
        Binding(get: { settings.followsCurrentLocation }, set: onSetFollowsCurrentLocation)
    }

    private var startsAtCurrentLocationBinding: Binding<Bool> {
        Binding(get: { settings.startsAtCurrentLocation }, set: onSetStartsAtCurrentLocation)
    }

    private var showsStopsBinding: Binding<Bool> {
        Binding(get: { settings.showsStops }, set: onSetShowsStops)
    }

    /// "30 s" for the short intervals, "2 min" for the long ones.
    static func intervalLabel(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return String(format: String(localized: "%lld s"), Int(interval))
        }
        return String(format: String(localized: "%lld min"), Int(interval / 60))
    }

    /// "Off", "250 m" or "1 km".
    static func radiusLabel(_ radius: Double) -> String {
        guard radius > 0 else { return String(localized: "Off") }
        if radius < 1_000 {
            return String(format: String(localized: "%lld m"), Int(radius.rounded()))
        }
        return String(format: String(localized: "%lld km"), Int((radius / 1_000).rounded()))
    }
}
