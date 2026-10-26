import Foundation

extension ServiceDay {
    /// The calendar day as a year, month and day, read the way the archive counts
    /// days: from midnight UTC, where a day really is 86,400 seconds long.
    var components: (year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Midnight UTC on this day. Only for arithmetic and for comparing days - it is
    /// never shown to the user as a time.
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(number) * 86_400)
    }

    /// 1 for Monday through 7 for Sunday, the numbering JDF writes in `Spoje.txt`
    /// and the one a "runs on Tuesdays" rule is read with.
    var weekday: Int {
        // 1 January 1970 was a Thursday, which is 4 in this numbering.
        ((number + 3) % 7) + 1
    }

    /// ISO week number, which is what the "odd weeks" and "even weeks" exceptions
    /// count in.
    var isoWeek: Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.component(.weekOfYear, from: date)
    }

    func adding(days: Int) -> ServiceDay {
        ServiceDay(number: number + days)
    }

    /// Days from `self` to `other`, negative when `other` is earlier.
    func distance(to other: ServiceDay) -> Int {
        other.number - number
    }
}
