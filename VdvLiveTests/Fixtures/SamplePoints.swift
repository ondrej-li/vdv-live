import Foundation

/// Payloads captured from `https://mapavdv.kr-vysocina.cz/Ajax/GetPoints`.
///
/// Kept as literals rather than bundle resources so the tests do not depend on
/// how the test bundle is assembled.
enum SamplePoints {
    /// Well formed response. Mirrors the quirks of the real feed: `\u` escaped
    /// diacritics, the `-2147483648` delay sentinel, `N/a` destinations, a
    /// negative id for a train and a vehicle parked at `0, 0`.
    static let valid = #"""
    [
      {"id":172923,"lat":49.39595413208008,"lng":16.366287231445312,"text":"841334","delay":5,"finalStopName":"Byst\u0159ice n.Pern.,aut.n\u00E1dr.","traction":"BUS"},
      {"id":173939,"lat":49.126838684082,"lng":16.252647399902344,"text":"841122","delay":-2147483648,"finalStopName":"Byst\u0159ice n.Pern.,aut.n\u00E1dr.","traction":"BUS"},
      {"id":-2435,"lat":49.594907,"lng":15.69692,"text":"5907","delay":1,"finalStopName":"5437035 N/a","traction":"TRAIN"},
      {"id":173669,"lat":49.31962,"lng":15.32854,"text":"358310","delay":0,"finalStopName":"27030 N/a","traction":"UNKNOWN"},
      {"id":173861,"lat":0,"lng":0,"text":"358304","delay":0,"finalStopName":"Pacov,aut.n\u00E1dr.","traction":"BUS"},
      {"id":173875,"lat":49.71385979652405,"lng":15.67996,"text":"609169","delay":-3,"finalStopName":"Chot\u011Bbo\u0159,ACHP","traction":"METRO"}
    ]
    """#

    /// Response where three of the five elements cannot be read: one element is
    /// not an object at all, one is missing a field and one has a coordinate of
    /// the wrong type.
    static let partiallyMalformed = #"""
    [
      {"id":1,"lat":49.39595413208008,"lng":16.366287231445312,"text":"841334","delay":5,"finalStopName":"Jihlava,aut.n\u00E1dr.","traction":"BUS"},
      42,
      {"id":3,"lat":49.2150,"lng":15.8810,"text":"764330","finalStopName":"T\u0159eb\u00ED\u010D,aut.n\u00E1dr.","traction":"BUS"},
      {"id":4,"lat":"not a number","lng":15.8810,"text":"764330","delay":0,"finalStopName":"T\u0159eb\u00ED\u010D,aut.n\u00E1dr.","traction":"BUS"},
      {"id":5,"lat":49.5627,"lng":15.9400,"text":"842135","delay":2,"finalStopName":"Nov\u00E9 M\u011Bsto na Mor.,centrum","traction":"BUS"}
    ]
    """#

    /// Valid JSON, but an object instead of the expected array.
    static let notAnArray = #"{"error":"upstream unavailable"}"#

    /// A `null` element between two valid records, which is what a feed that
    /// builds its array by concatenating fragments tends to produce.
    static let withNullRecord = #"""
    [
      null,
      {"id":1,"lat":49.39595413208008,"lng":16.366287231445312,"text":"841334","delay":5,"finalStopName":"Jihlava,aut.n\u00E1dr.","traction":"BUS"}
    ]
    """#

    /// What a proxy or a captive portal likes to answer with.
    static let notJSON = "<html><body>Service Unavailable</body></html>"

    /// Valid JSON array without a single vehicle.
    static let emptyArray = "[]"
}
