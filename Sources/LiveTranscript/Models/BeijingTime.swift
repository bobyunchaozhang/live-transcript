import Foundation

enum BeijingTime {
    static let zone = TimeZone(secondsFromGMT: 8 * 3600)!

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }()

    static func clock(_ date: Date) -> String {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", time.hour ?? 0, time.minute ?? 0, time.second ?? 0)
    }

    static func dateAndTime(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: zone)
            .year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: false).timeSeparator(.colon)
            .dateTimeSeparator(.space).timeZone(separator: .colon))
    }
}
