import SwiftUI

/// Where the data comes from.
///
/// The timetable dataset is published under CC BY 4.0 with the sui generis
/// database right, which obliges anything built on it to say so - and a licence
/// note hidden in a JSON file or in the repository is not attribution a user can
/// find. All of this is static text, so it reads offline.
struct AcknowledgementsView: View {
    var body: some View {
        Form {
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
                Text("The base map and its tiles are Apple Maps, drawn through MapKit.")
            } header: {
                Text("Maps")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
