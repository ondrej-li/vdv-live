import Foundation

/// The days Czech timetables treat as holidays.
///
/// This matters more than it looks. A JDF run marked `X` runs on working days and
/// **not** on a public holiday, while one marked `+` runs on Sundays *and* on
/// public holidays - so a calendar that ignored 28 October would send a "your bus
/// leaves at 7:42" reminder on a day the bus does not run, and skip one on a day it
/// does.
///
/// The list is the statutory one: the fixed dates below, plus Good Friday and
/// Easter Monday, which move with Easter.
enum CzechHolidays {
    /// Whether `day` is a public holiday in Czechia.
    static func isHoliday(_ day: ServiceDay) -> Bool {
        holidays(in: day.components.year).contains(day)
    }

    /// Every public holiday in `year`.
    static func holidays(in year: Int) -> Set<ServiceDay> {
        var days: Set<ServiceDay> = [
            day(year, 1, 1),     // Nový rok a Den obnovy samostatného českého státu
            day(year, 5, 1),     // Svátek práce
            day(year, 5, 8),     // Den vítězství
            day(year, 7, 5),     // Cyril a Metoděj
            day(year, 7, 6),     // Jan Hus
            day(year, 9, 28),    // Den české státnosti
            day(year, 10, 28),   // Den vzniku samostatného československého státu
            day(year, 11, 17),   // Den boje za svobodu a demokracii
            day(year, 12, 24),   // Štědrý den
            day(year, 12, 25),   // 1. svátek vánoční
            day(year, 12, 26)    // 2. svátek vánoční
        ]
        let easter = easterSunday(year: year)
        days.insert(easter.adding(days: -2))  // Good Friday
        days.insert(easter.adding(days: 1))   // Easter Monday
        return days
    }

    /// Easter Sunday in the Gregorian calendar, by the anonymous Gregorian
    /// computus.
    static func easterSunday(year: Int) -> ServiceDay {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let dayOfMonth = ((h + l - 7 * m + 114) % 31) + 1
        return day(year, month, dayOfMonth)
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> ServiceDay {
        ServiceDay(year: year, month: month, day: day)
    }
}
