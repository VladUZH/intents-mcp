import Foundation

public enum Classifier {
    /// supportedModes is a bit field; on macOS 27, 1 always pairs with openAppWhenRun:false and 2 with
    /// true (tech-notes §1.2, inference), so 1 = background, 2 = foreground.
    public static func modes(_ raw: RawAction) -> [String] {
        guard let m = raw.supportedModes else {
            if let open = raw.openAppWhenRun { return [open ? "foreground" : "background"] }
            return []
        }
        var out: [String] = []
        if m & 1 != 0 { out.append("background") }
        if m & 2 != 0 { out.append("foreground") }
        for bit in 2..<16 where m & (1 << bit) != 0 { out.append("mode-\(1 << bit)") }
        return out
    }

    public static func opensApp(_ raw: RawAction) -> Bool {
        if raw.openAppWhenRun == true { return true }
        let m = modes(raw)
        return !m.contains("background") && m.contains("foreground")
    }

    /// Words that suggest deleting, sending, purchasing or sharing (CLAUDE.md non-negotiable 2), with
    /// their common inflections (tokens are whole words, so "deleted" doesn't match "delete").
    static let riskyWords: Set<String> = [
        "delete", "deletes", "deleted", "deleting", "deletion",
        "remove", "removes", "removed", "removing", "removal",
        "trash", "trashes", "trashed", "erase", "erases", "erased", "clear", "clears", "cleared", "empty", "emptied",
        "unsend", "send", "sends", "sent", "sending", "reply", "replies", "replied", "forward", "forwards", "forwarded",
        "call", "calls", "calling", "post", "posts", "posted", "publish", "publishes", "published",
        "purchase", "purchases", "purchased", "buy", "buys", "bought", "pay", "pays", "paid", "payment", "payments",
        "transfer", "transfers", "order", "orders", "ordered", "subscribe", "subscribes", "unsubscribe", "subscription",
        "share", "shares", "shared", "sharing", "invite", "invites", "invited", "inviting", "invitation",
        "unsave", "paying", "buying", "ordering", "transferred", "transferring", "subscribed", "posting",
        "replying", "forwarding", "erasing", "trashing", "emptying", "discard", "discards", "discarded", "wipe", "wiped",
    ]

    /// Names or descriptions (CLAUDE.md non-negotiable 2).
    public static func risk(_ raw: RawAction) -> [String] {
        var reasons: [String] = []
        if raw.systemProtocols.contains(where: { $0.hasSuffix("DeleteEntity") }) { reasons.append("DeleteEntity protocol") }
        let words = Set(tokens(raw.identifier) + tokens(raw.title))
        for w in words.intersection(riskyWords).sorted() { reasons.append("name: \(w)") }
        let described = Set(tokens(raw.description ?? "")).intersection(riskyWords).subtracting(words)
        for w in described.sorted() { reasons.append("description: \(w)") }
        return reasons
    }

    public static func tier(_ raw: RawAction) -> (Tier, [String]) {
        var reasons: [String] = []
        if !raw.discoverable { reasons.append("not discoverable in Shortcuts") }
        let words = Set(tokens(raw.identifier) + tokens(raw.title))
        if !words.isDisjoint(with: ["test", "debug"]) { reasons.append("looks internal (test/debug)") }
        if !raw.availableOnMac { reasons.append("unavailable on macOS") }
        let m = modes(raw)
        if opensApp(raw) { reasons.append("opens the app") } else if !m.contains("background") { reasons.append("run mode unknown") }
        if raw.outputType == nil { reasons.append("returns no output") }
        let entity = raw.parameters.filter { $0.kind.needsEntity }
        let complex = raw.parameters.filter { !$0.kind.isSimple && !$0.kind.needsEntity }
        for p in entity { reasons.append("takes an entity: \(p.name)") }
        for p in complex {
            if case .enumeration(_, let cases) = p.kind, cases.isEmpty {
                reasons.append("unsupported input: \(p.name) (choice list not in the metadata)")
            } else {
                reasons.append("unsupported input: \(p.name) (\(p.kind.label))")
            }
        }
        if reasons.isEmpty { return (.simple, []) }
        if !entity.isEmpty && raw.discoverable && raw.availableOnMac { return (.needsEntity, reasons) }
        return (.unsupported, reasons)
    }

    /// "TTRCreateReminderAppIntent" → ["ttr", "create", "reminder", "app", "intent"].
    public static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        let chars = Array(s)
        for (i, ch) in chars.enumerated() {
            guard ch.isLetter || ch.isNumber else {
                if !cur.isEmpty { out.append(cur) }
                cur = ""
                continue
            }
            let prev = i > 0 ? chars[i - 1] : nil
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            // New word at lower→Upper ("teR"), and at the last capital of an acronym ("TTRCreate").
            if ch.isUppercase, !cur.isEmpty,
               prev?.isLowercase == true || prev?.isNumber == true || (prev?.isUppercase == true && next?.isLowercase == true) {
                out.append(cur)
                cur = ""
            }
            cur.append(ch)
        }
        if !cur.isEmpty { out.append(cur) }
        return out.map { $0.lowercased() }
    }

    public static func slug(_ s: String) -> String {
        let parts = s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return parts.joined(separator: "-")
    }
}
