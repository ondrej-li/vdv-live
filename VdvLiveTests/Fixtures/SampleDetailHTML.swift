import Foundation

/// Markup captured from the map's own AJAX endpoints.
///
/// Both endpoints answer with HTML rather than JSON, so the parser is tested
/// against real responses, escapes and all.
enum SampleDetailHTML {
    /// `GET /Ajax/OpenInfoWindow?id=173067`, vehicle 764931 / run 11.
    static let infoWindow = #"""
    <div class="table-container">
        <table class="table is-striped is-fullwidth">
            <tbody>
                <tr>
                    <th>Linka</th>
                    <td>764931</td>
                </tr>
                <tr>
                    <th>Spoj</th>
                    <td>11</td>
                </tr>
                <tr>
                    <th>Bezbarierov&#xFD;</th>
                    <td>
                            <input type="checkbox" disabled>
                    </td>
                </tr>
                <tr>
                    <th>Zast&#xE1;vka</th>
                    <td>Tel&#x10D;,Hradeck&#xE1; &#x161;kola</td>
                </tr>
                <tr>
                    <th>Zpo&#x17E;d&#x11B;n&#xED;</th>
                    <td>0 min.</td>
                </tr>
            </tbody>
        </table>
        <button class="button is-small is-info is-outlined" onclick="inflow.InfoWindow.loadTimetable(173067, 0)">
            <span class="icon is-small">
                <i class="fas fa-table"></i>
            </span>
            <span>J&#xED;zdn&#xED; &#x159;&#xE1;d</span>
        </button>
    </div>
    """#

    /// Same endpoint for a vehicle that is accessible and running late.
    static let infoWindowBarrierFreeAndLate = #"""
    <table>
        <tbody>
            <tr><th>Linka</th><td>841334</td></tr>
            <tr><th>Spoj</th><td>9</td></tr>
            <tr><th>Bezbarierov&#xFD;</th><td><input type="checkbox" checked disabled></td></tr>
            <tr><th>Zast&#xE1;vka</th><td>Pelh&#x159;imov,aut.n&#xE1;dr.</td></tr>
            <tr><th>Zpo&#x17E;d&#x11B;n&#xED;</th><td>-3 min.</td></tr>
        </tbody>
    </table>
    """#

    /// Same endpoint for a vehicle the feed has no delay for. The column carries
    /// `Int32.min` rather than a number of minutes.
    static let infoWindowWithoutADelay = #"""
    <table>
        <tbody>
            <tr><th>Linka</th><td>764337</td></tr>
            <tr><th>Spoj</th><td>337</td></tr>
            <tr><th>Bezbarierov&#xFD;</th><td><input type="checkbox" disabled></td></tr>
            <tr><th>Zast&#xE1;vka</th><td>Petrovice</td></tr>
            <tr><th>Zpo&#x17E;d&#x11B;n&#xED;</th><td>-2147483648 min.</td></tr>
        </tbody>
    </table>
    """#

    /// `GET /Ajax/GetTimetable?vehicleNumber=173067&currentStopId=0`, trimmed
    /// to the first five stops of the run.
    static let timetable = #"""
    <div class="column has-text-centered">
        <span style="font-weight:bold;margin-right: 10px;">Linkospoj:</span>
        <span>764931 / 11</span>
        <span>-- / --</span>
    </div>
    <table class="table is-striped is-fullwidth">
        <thead>
            <tr>
                <th>Zast&#xE1;vka</th>
                <th class="has-text-centered" style="width:100px">P&#x159;&#xED;jezd</th>
                <th class="has-text-centered" style="width:100px">Odjezd</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Tel&#x10D;,aut.n&#xE1;dr.</td>
                <td class="has-text-centered">14:06</td>
                <td class="has-text-centered">14:06</td>
            </tr>
            <tr>
                <td>Tel&#x10D;,Hradeck&#xE1; &#x161;kola</td>
                <td class="has-text-centered">14:12</td>
                <td class="has-text-centered">14:12</td>
            </tr>
            <tr>
                <td>Host&#x11B;tice</td>
                <td class="has-text-centered">14:16</td>
                <td class="has-text-centered">14:16</td>
            </tr>
            <tr>
                <td>Host&#x11B;tice,&#x10C;&#xE1;stkovice</td>
                <td class="has-text-centered">14:18</td>
                <td class="has-text-centered">14:18</td>
            </tr>
            <tr>
                <td>Mr&#xE1;kot&#xED;n</td>
                <td class="has-text-centered">14:21</td>
                <td class="has-text-centered">14:21</td>
            </tr>
        </tbody>
    </table>
    """#

    /// A request stop has no times at all.
    static let timetableWithEmptyTimes = #"""
    <table>
        <tbody>
            <tr>
                <td>Jihlava,aut.n&#xE1;dr.</td>
                <td class="has-text-centered">--</td>
                <td class="has-text-centered">--</td>
            </tr>
            <tr>
                <td>Jihlava,ZOO</td>
                <td class="has-text-centered">10:15</td>
                <td class="has-text-centered">--</td>
            </tr>
        </tbody>
    </table>
    """#

    /// `GET /Ajax/OpenInfoWindow?id=173213`, captured 14 November 2026.
    ///
    /// The site renders the popup as a description list now, and it names the line
    /// and the run together: `Linka / spoj` → `766420 / 109`. Reading only the old
    /// table left the card with no run, and therefore with no stop list at all.
    static let infoWindowFacts = #"""
    <div class="panel-sticky">
    <div class="delay">
        <span class="delay-value">V&#x10D;as</span>
        <span class="delay-label"></span>
    </div>
    </div>

    <div id="infoTabContent" role="tabpanel" aria-labelledby="infoTab">
        <dl class="facts">
            <div>
                <dt>Posledn&#xED; zast&#xE1;vka</dt>
                <dd>Jihlava,BOSCH P&#xE1;vov</dd>
            </div>
            <div>
                <dt>Linka / spoj</dt>
                <dd>766420 / 109</dd>
            </div>
            <div>
                <dt>Bezbari&#xE9;rov&#xE9; vozidlo</dt>
                <dd>
    Ne            </dd>
            </div>
            <div>
                <dt>&#x10C;&#xED;slo vozidla</dt>
                <dd>4-4471</dd>
            </div>
        </dl>
    </div>
    """#

    /// The same markup for a vehicle running late, captured with `id=173050`.
    static let infoWindowFactsLate = #"""
    <div class="panel-sticky">
    <div class="delay">
        <span class="delay-value">&#x2B;22 min</span>
        <span class="delay-label">zpo&#x17E;d&#x11B;n&#xED;</span>
    </div>
    </div>

    <div id="infoTabContent" role="tabpanel" aria-labelledby="infoTab">
        <dl class="facts">
            <div>
                <dt>Posledn&#xED; zast&#xE1;vka</dt>
                <dd>St&#x159;&#xED;te&#x17E;,JIPOCAR</dd>
            </div>
            <div>
                <dt>Linka / spoj</dt>
                <dd>842182 / 7</dd>
            </div>
            <div>
                <dt>Bezbari&#xE9;rov&#xE9; vozidlo</dt>
                <dd>
    Ne            </dd>
            </div>
        </dl>
    </div>
    """#

    /// `GET /Ajax/GetTimetable?vehicleNumber=173213&currentStopId=68243`, captured the
    /// same day and cut to five stops.
    ///
    /// One time column - "Plán" - rather than an arrival and a departure column, the
    /// stop the vehicle is at marked with `is-current`, and its arrival inside the
    /// name cell.
    static let timetableRideCaption = #"""
    <div id="timetableCurrentContainer">
            <p class="ride-caption">Linka 766420, spoj 109</p>
            <table class="timetable">
                <thead>
                    <tr>
                        <th>Zast&#xE1;vka</th>
                        <th class="time">Pl&#xE1;n</th>
                    </tr>
                </thead>
                <tbody>
                        <tr class="is-current" aria-current="location">
                            <td>
                                Jihlava,BOSCH P&#xE1;vov
                            </td>
                            <td class="time">22:17</td>
                        </tr>
                        <tr>
                            <td>
                                Jihlava,&#x160;kola Bed&#x159;ichov
                            </td>
                            <td class="time">22:20</td>
                        </tr>
                        <tr>
                            <td>
                                Jihlava,aut.n&#xE1;dr.
                                    <span class="stop-arrival">p&#x159;&#xED;jezd 22:31</span>
                            </td>
                            <td class="time">22:40</td>
                        </tr>
                        <tr>
                            <td>
                                Puklice,Stud&#xE9;nky
                            </td>
                            <td class="time">22:51</td>
                        </tr>
                        <tr>
                            <td>
                                Brtnice,n&#xE1;m.
                            </td>
                            <td class="time">23:07</td>
                        </tr>
                </tbody>
            </table>
    </div>
    """#
}
