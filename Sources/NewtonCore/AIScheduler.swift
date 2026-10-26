import Foundation

public enum AIScheduleMode: String, Sendable, Codable, Equatable {
    case daytimeUserReserve
    case nighttimeAutonomous
}

public struct ExecutionDecision: Sendable, Equatable {
    public let allowed: Bool
    public let mode: AIScheduleMode
    public let reason: String

    public init(allowed: Bool, mode: AIScheduleMode, reason: String) {
        self.allowed = allowed
        self.mode = mode
        self.reason = reason
    }
}

public struct AIScheduler: Sendable {
    public let daytimeStartHour: Int
    public let daytimeEndHour: Int
    public let daytimeMaxQuotaUse: Double
    public let nighttimeMaxQuotaUse: Double

    public init(daytimeStartHour: Int = 8,
                daytimeEndHour: Int = 22,
                daytimeMaxQuotaUse: Double = 30.0,
                nighttimeMaxQuotaUse: Double = 90.0) {
        self.daytimeStartHour = daytimeStartHour
        self.daytimeEndHour = daytimeEndHour
        self.daytimeMaxQuotaUse = daytimeMaxQuotaUse
        self.nighttimeMaxQuotaUse = nighttimeMaxQuotaUse
    }

    public func currentMode(at date: Date = Date(), calendar: Calendar = .current) -> AIScheduleMode {
        let hour = calendar.component(.hour, from: date)
        if hour >= daytimeStartHour && hour < daytimeEndHour {
            return .daytimeUserReserve
        } else {
            return .nighttimeAutonomous
        }
    }

    public func canExecuteAutonomousJob(now: Date = Date(),
                                        quota: CodexQuota?,
                                        calendar: Calendar = .current,
                                        userWakeHour: Int = 8) -> ExecutionDecision {
        return ExecutionDecision(allowed: false, mode: currentMode(at: now, calendar: calendar),
                                 reason: "Unattended execution is disabled. Use the owned manual runner; quota is advisory.")
    }

    /// Advisory snapshot assessment only; never authorizes unattended execution.
    public func evaluateQuotaPolicy(now: Date = Date(),
                                    quota: CodexQuota?,
                                    calendar: Calendar = .current,
                                    userWakeHour: Int = 8) -> ExecutionDecision {
        let mode = currentMode(at: now, calendar: calendar)
        guard let quota = quota else {
            return ExecutionDecision(allowed: false, mode: mode, reason: "Quota snapshot is not available.")
        }
        let used = quota.primary.usedPercent
        switch mode {
        case .daytimeUserReserve:
            if used > daytimeMaxQuotaUse {
                return ExecutionDecision(allowed: false, mode: mode,
                    reason: "Advisory: daytime reserve threshold: usage (\(Int(used))%) exceeds daytime limit (\(Int(daytimeMaxQuotaUse))%).")
            } else {
                return ExecutionDecision(allowed: true, mode: mode,
                    reason: "Advisory: daytime usage (\(Int(used))%) is within acceptable reserve threshold (\(Int(daytimeMaxQuotaUse))%).")
            }
        case .nighttimeAutonomous:
            if used > nighttimeMaxQuotaUse {
                return ExecutionDecision(allowed: false, mode: mode,
                    reason: "Advisory: nighttime threshold exceeded (\(Int(used))% > \(Int(nighttimeMaxQuotaUse))%).")
            }
            // Check if 5-hour rolling window resets after user morning wake time
            var wakeComps = calendar.dateComponents([.year, .month, .day], from: now)
            wakeComps.hour = userWakeHour
            wakeComps.minute = 0
            if let wakeDate = calendar.date(from: wakeComps) {
                let actualWakeDate = wakeDate < now ? (calendar.date(byAdding: .day, value: 1, to: wakeDate) ?? wakeDate) : wakeDate
                if quota.primary.resetsAt > actualWakeDate && used > daytimeMaxQuotaUse {
                    return ExecutionDecision(allowed: false, mode: mode,
                        reason: "Rolling 5h window reset (\(quota.primary.resetsAt.formatted(date: .omitted, time: .shortened))) falls after morning wake time (\(userWakeHour):00). Consider conserving quota; reset times do not guarantee future capacity.")
                }
            }
            return ExecutionDecision(allowed: true, mode: mode,
                reason: "Advisory: snapshot is within the nighttime threshold. Future capacity and morning quota are not guaranteed.")
        }
    }
}
