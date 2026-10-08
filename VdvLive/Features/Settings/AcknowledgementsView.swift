import SwiftUI

/// Where the data comes from, and who to tell when something is wrong.
///
/// The timetable dataset is published under CC BY 4.0 with the sui generis
/// database right, which obliges anything built on it to say so - and a licence
/// note hidden in a JSON file or in the repository is not attribution a user can
/// find. All of this is static text, so it reads offline.
struct AcknowledgementsView: View {
    /// Where feedback goes. The subject is filled in, so that a message sent from
    /// this screen is recognisable in an inbox.
    private static let feedbackAddress = "ondrej.linek@gmail.com"
    private static let feedbackLink = URL(
        string: "mailto:ondrej.linek@gmail.com?subject=VDV%20Live%20feedback"
    )!

    var body: some View {
        Form {
            Section {
                Text("VDV Live is written and maintained by Ondrej Linek.")
                Link(Self.feedbackAddress, destination: Self.feedbackLink)
            } header: {
                Text("The app")
            } footer: {
                Text("Feedback, bug reports and feature requests are welcome there.")
            }

            Section {
                Text("Positions come from the regional map of the Vysočina Region at mapavdv.kr-vysocina.cz. This app is not affiliated with the region or with the transport operators.")
            } header: {
                Text("Live vehicle positions")
            }

            Section {
                Text("Timetables come from “Jízdní řády veřejné linkové dopravy”, published by the Ministry of Transport of the Czech Republic (IČO 66003008) on the CIS JŘ portal at portal.cisjr.cz, under the Creative Commons Attribution 4.0 licence (creativecommons.org/licenses/by/4.0/) and the sui generis database right.")
            } header: {
                Text("Timetables")
            }

            Section {
                Text("Stop positions are matched from OpenStreetMap by stop name, and the app icon is drawn from its roads and rivers. The data is © OpenStreetMap contributors, published under the Open Database Licence 1.0 (openstreetmap.org/copyright).")
            } header: {
                Text("OpenStreetMap")
            }

            Section {
                Text("The base map and its tiles are Apple Maps, drawn through MapKit.")
            } header: {
                Text("Maps")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
