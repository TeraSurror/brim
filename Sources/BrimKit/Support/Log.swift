import os

enum Log {
    static let subsystem = "com.harshshelar.brim"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let state = Logger(subsystem: subsystem, category: "state")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let agent = Logger(subsystem: subsystem, category: "agent")
}
