import Foundation

/// Pure event policy; uptime is monotonic and synthetic forwarding is explicitly tagged.
public struct KeyboardPolicy: Sendable {
    public enum Result: Sendable, Equatable { case pass, swallow, unlock, holdStarted, holdCancelled }
    public var cleaning = false
    public private(set) var escapePresses = 0
    public private(set) var heldKey: Int64?
    public private(set) var heldBundle: String?
    public private(set) var deadline: TimeInterval?
    private var consumedKeys = Set<Int64>()
    private var forwarded = false
    private var escapeIsDown = false
    public init() {}
    public mutating func cancel() {
        heldKey = nil; heldBundle = nil; deadline = nil; forwarded = false
    }
    public mutating func reset() { cancel(); consumedKeys.removeAll(); cleaning = false; escapePresses = 0; escapeIsDown = false }
    public mutating func handle(key: Int64, down: Bool, command: Bool, repeatKey: Bool, synthetic: Bool,
                                bundle: String?, protected: Bool, now: TimeInterval, duration: TimeInterval) -> Result {
        if synthetic { return .pass }
        if cleaning {
            cancel()
            if key == 53 && !down { escapeIsDown = false; return .swallow }
            if key == 53 && (repeatKey || escapeIsDown) { return .swallow }
            if down && !repeatKey {
                if key == 53 { escapeIsDown = true; escapePresses += 1 } else { escapePresses = 0 }
                if escapePresses == 5 { cleaning = false; escapePresses = 0; return .unlock }
            }
            return .swallow
        }
        if heldBundle != nil && heldBundle != bundle { cancel() }
        if !down {
            let consumed = consumedKeys.remove(key) != nil
            if heldKey == key { cancel(); return .holdCancelled }
            return consumed ? .swallow : .pass
        }
        if consumedKeys.contains(key) { return .swallow }
        guard command, protected, key == 12 || key == 13, !repeatKey, let bundle else { return .pass }
        consumedKeys.insert(key); heldKey = key; heldBundle = bundle
        deadline = now + max(0.2, duration); forwarded = false
        return .holdStarted
    }
    public mutating func complete(now: TimeInterval, bundle: String?) -> Int64? {
        guard let key = heldKey, let deadline, heldBundle == bundle, now >= deadline, !forwarded, !cleaning else { return nil }
        forwarded = true
        return key
    }
}
