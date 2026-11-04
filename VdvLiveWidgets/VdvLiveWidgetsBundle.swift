import SwiftUI
import WidgetKit

/// The two widgets the app adds to the home screen.
@main
struct VdvLiveWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DepartureBoardWidget()
        StarredTrafficWidget()
    }
}
