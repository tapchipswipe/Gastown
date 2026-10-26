import Foundation

public struct CommandBarAction: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: String
    public let iconName: String

    public init(id: String, title: String, subtitle: String, category: String, iconName: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.iconName = iconName
    }
}

/// On-device calculation, conversion, and quick command evaluator for Newton's ⌘K Command Bar.
public enum CommandBarEngine: Sendable {
    public static let standardActions: [CommandBarAction] = [
        CommandBarAction(id: "standup", title: "Synthesize Daily Standup", subtitle: "Generate engineering standup note from daily activity & git", category: "Pipe", iconName: "doc.text.fill"),
        CommandBarAction(id: "missedTodos", title: "Run Missed To-Dos Pipe", subtitle: "Scan timeline for unfulfilled commitments and action items", category: "Pipe", iconName: "checklist.checked"),
        CommandBarAction(id: "snapLeft", title: "Snap Window Left", subtitle: "Tile frontmost window to left 50%", category: "Window", iconName: "rectangle.leadinghalf.filled"),
        CommandBarAction(id: "snapRight", title: "Snap Window Right", subtitle: "Tile frontmost window to right 50%", category: "Window", iconName: "rectangle.trailinghalf.filled"),
        CommandBarAction(id: "snapMax", title: "Maximize Window", subtitle: "Expand frontmost window to fill screen", category: "Window", iconName: "rectangle.inset.filled"),
        CommandBarAction(id: "snapCenter", title: "Center Window", subtitle: "Center frontmost window on screen", category: "Window", iconName: "rectangle.center.inset.filled"),
        CommandBarAction(id: "ports", title: "Developer Port Manager", subtitle: "Inspect localhost listening sockets and kill hung processes", category: "Tools", iconName: "network"),
        CommandBarAction(id: "ghostStorage", title: "Inspect iCloud Ghost Files", subtitle: "Measure dataless cloud ghost ratios and evict local caches", category: "Storage", iconName: "icloud.fill"),
        CommandBarAction(id: "bloat", title: "Trim Developer Caches", subtitle: "Scan and clean node_modules, .venv, target folders", category: "Clean", iconName: "trash.fill"),
        CommandBarAction(id: "keepAwake", title: "Toggle Keep Awake", subtitle: "Prevent macOS display and system sleep", category: "System", iconName: "cup.and.saucer.fill"),
        CommandBarAction(id: "eyedropper", title: "Sample Screen Color", subtitle: "Pick color under cursor and copy hex code", category: "Tools", iconName: "eyedropper"),
        CommandBarAction(id: "mute", title: "Toggle Microphone Mute", subtitle: "Hardware/input level mute toggle", category: "System", iconName: "mic.slash.fill"),
        CommandBarAction(id: "notch", title: "Toggle Dynamic Notch Island", subtitle: "Show or hide the desktop notch overlay", category: "Interface", iconName: "macbook.gen2"),
        CommandBarAction(id: "hud", title: "Toggle Desktop Glass HUD", subtitle: "Show or hide the draggable focus HUD", category: "Interface", iconName: "gauge.with.dots.needle.50percent"),
        CommandBarAction(id: "shelf", title: "Toggle Floating Drop Shelf", subtitle: "Show or hide the file and snippet staging tray", category: "Interface", iconName: "tray.and.arrow.down.fill"),
        CommandBarAction(id: "cleanMode", title: "Toggle Keyboard Cleaning Mode", subtitle: "Lock keyboard to wipe down screen and keys safely", category: "Tools", iconName: "keyboard"),
        CommandBarAction(id: "pinMoment", title: "Pin Desktop Snippet", subtitle: "Pin active window or OCR moment floating on desktop", category: "Tools", iconName: "pin.fill"),
        CommandBarAction(id: "closePins", title: "Close All Desktop Pins", subtitle: "Dismiss all floating pinned snippet windows", category: "Tools", iconName: "xmark.circle.fill"),
        CommandBarAction(id: "quitProtect", title: "Quit Protection Settings", subtitle: "Manage accidental ⌘Q and ⌘W protection", category: "Settings", iconName: "shield.checkered")
    ]

    /// Evaluates arithmetic expressions safely (e.g., "2 + 2 * 3" -> "= 8").
    public static func evaluateMath(_ expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Must contain at least one mathematical operator or function to avoid treating plain words as formulas
        let mathPattern = "^[0-9\\.\\s\\+\\-\\*/\\(\\)\\^%]+$"
        guard trimmed.range(of: mathPattern, options: .regularExpression) != nil else { return nil }
        guard trimmed.contains("+") || trimmed.contains("-") || trimmed.contains("*") || trimmed.contains("/") || trimmed.contains("%") else {
            return nil
        }

        // Clean formula
        let formula = trimmed.replacingOccurrences(of: " ", with: "")
        let expr = NSExpression(format: formula)
        guard let result = expr.expressionValue(with: nil, context: nil) else { return nil }

        if let doubleVal = result as? Double {
            if doubleVal.isFinite {
                if floor(doubleVal) == doubleVal && abs(doubleVal) < 1e12 {
                    return "= \(Int(doubleVal))"
                } else {
                    return String(format: "= %.4g", doubleVal)
                }
            }
        } else if let num = result as? NSNumber {
            return "= \(num)"
        }
        return nil
    }

    /// Evaluates unit conversion queries (e.g. "100 km to mi", "32 c to f", "1024 mb to gb").
    public static func convertUnits(_ query: String) -> String? {
        let parts = query.lowercased().split(separator: " ").map(String.init)
        guard parts.count >= 4, parts[2] == "to" || parts[2] == "in" else { return nil }

        guard let value = Double(parts[0]) else { return nil }
        let fromUnit = parts[1]
        let toUnit = parts[3]

        switch (fromUnit, toUnit) {
        // Distance
        case ("km", "mi"), ("kilometers", "miles"), ("kilometer", "mile"):
            return String(format: "%.2f mi", value * 0.621371)
        case ("mi", "km"), ("miles", "kilometers"), ("mile", "kilometer"):
            return String(format: "%.2f km", value * 1.60934)
        case ("m", "ft"), ("meters", "feet"), ("meter", "foot"):
            return String(format: "%.2f ft", value * 3.28084)
        case ("ft", "m"), ("feet", "meters"), ("foot", "meter"):
            return String(format: "%.2f m", value * 0.3048)

        // Temperature
        case ("c", "f"), ("celsius", "fahrenheit"):
            let f = (value * 9.0 / 5.0) + 32.0
            return String(format: "%.1f °F", f)
        case ("f", "c"), ("fahrenheit", "celsius"):
            let c = (value - 32.0) * 5.0 / 9.0
            return String(format: "%.1f °C", c)

        // Storage / Data
        case ("mb", "gb"):
            return String(format: "%.2f GB", value / 1024.0)
        case ("gb", "mb"):
            return String(format: "%.0f MB", value * 1024.0)
        case ("gb", "tb"):
            return String(format: "%.3f TB", value / 1024.0)
        case ("tb", "gb"):
            return String(format: "%.0f GB", value * 1024.0)

        // Weight
        case ("kg", "lbs"), ("kg", "lb"), ("kilograms", "pounds"):
            return String(format: "%.2f lbs", value * 2.20462)
        case ("lbs", "kg"), ("lb", "kg"), ("pounds", "kilograms"):
            return String(format: "%.2f kg", value * 0.453592)

        default:
            return nil
        }
    }

    /// Filters commands matching query.
    public static func matchActions(query: String) -> [CommandBarAction] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return standardActions }
        return standardActions.filter {
            $0.title.lowercased().contains(q) ||
            $0.subtitle.lowercased().contains(q) ||
            $0.category.lowercased().contains(q)
        }
    }
}

