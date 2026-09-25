import Foundation

/// Counts for `intents-mcp census`: what this Mac *declares* in App Intents metadata.
/// Not the same as what works through Shortcuts (M0: some declared intents are refused at import,
/// and Reminders/Calendar run through built-in Shortcuts actions that are not in this metadata).
public struct Census: Codable, Sendable, Equatable {
    public var metadataFiles: Int
    public var declaredActions: Int
    public var uniqueActions: Int
    public var apps: Int
    public var discoverable: Int
    public var byTier: [String: Int]
    public var risky: Int
    public var thirdParty: ThirdParty
    public var topApps: [AppCount]

    public struct ThirdParty: Codable, Sendable, Equatable {
        public var apps: Int
        public var actions: Int
        public var discoverable: Int
        public var simple: Int
    }

    public struct AppCount: Codable, Sendable, Equatable {
        public var app: String
        public var bundleID: String
        public var actions: Int
        public var simple: Int
    }

    public init(_ index: ActionIndex, top: Int = 15) {
        let a = index.actions
        metadataFiles = index.files.count
        declaredActions = index.declaredCount
        uniqueActions = a.count
        apps = Set(a.map(\.app.bundleID)).count
        discoverable = a.filter(\.discoverable).count
        byTier = Dictionary(uniqueKeysWithValues: Tier.allCases.map { t in (t.rawValue, a.filter { $0.tier == t }.count) })
        risky = a.filter(\.risky).count
        let third = a.filter { $0.app.teamID != "0000000000" }
        thirdParty = ThirdParty(apps: Set(third.map(\.app.bundleID)).count, actions: third.count,
                                discoverable: third.filter(\.discoverable).count,
                                simple: third.filter { $0.tier == .simple }.count)
        let grouped = Dictionary(grouping: a, by: \.app.bundleID)
        topApps = grouped.map { id, xs in
            AppCount(app: xs[0].app.name, bundleID: id, actions: xs.count, simple: xs.filter { $0.tier == .simple }.count)
        }
        .sorted { ($0.actions, $1.app) > ($1.actions, $0.app) }
        .prefix(top).map { $0 }
    }
}
