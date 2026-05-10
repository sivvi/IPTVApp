import OSLog

enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.iptvapp"

    static let player = os.Logger(subsystem: subsystem, category: "Player")
    static let parser = os.Logger(subsystem: subsystem, category: "Parser")
    static let network = os.Logger(subsystem: subsystem, category: "Network")
    static let casting = os.Logger(subsystem: subsystem, category: "Casting")
    static let database = os.Logger(subsystem: subsystem, category: "Database")
    static let general = os.Logger(subsystem: subsystem, category: "General")
}
