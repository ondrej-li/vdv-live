import Foundation

/// Where the app's long lived objects come from.
///
/// Deliberately small: one place knows how to build the live stack, and every
/// screen takes the pieces it needs. That keeps tests and previews free to pass
/// in their own ``VehicleFetching`` instead.
struct AppDependencies: Sendable {
    let vehicleFetcher: VehicleFetching
    let favouriteLinesStore: FavouriteLinesPersisting
    let settingsStore: AppSettingsStoring
    let detailFetcher: VehicleDetailFetching

    /// Live stack, reading the regional feed over the network and keeping the
    /// pinned lines in the app's user defaults.
    static let live = AppDependencies(
        vehicleFetcher: VehicleAPIClient(),
        favouriteLinesStore: UserDefaultsFavouriteLinesStore(),
        settingsStore: UserDefaultsAppSettingsStore(),
        detailFetcher: VehicleDetailClient()
    )
}

#if DEBUG
extension AppDependencies {
    /// Stack used by SwiftUI previews: no network, fixed sample data, and a
    /// couple of lines already pinned so the star markers show up.
    static let preview = AppDependencies(
        vehicleFetcher: SampleVehicleFetcher(),
        favouriteLinesStore: InMemoryFavouriteLinesStore(
            lines: FavouriteLines(["841334", "357301"]),
            showsOnlyFavourites: true
        ),
        settingsStore: InMemoryAppSettingsStore(),
        detailFetcher: SampleVehicleDetailFetcher()
    )
}
#endif
