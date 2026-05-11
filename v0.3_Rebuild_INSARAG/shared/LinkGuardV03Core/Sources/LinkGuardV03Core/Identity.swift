import Foundation

public struct LinkGuardID: Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }

    public static func generated(prefix: String = "LG") -> LinkGuardID {
        LinkGuardID("\(prefix)-\(UUID().uuidString)")
    }
}

public enum LinkGuardAppID: String, Codable, CaseIterable, Sendable {
    case ucc = "LinkGuard-UCC"
    case scc = "LinkGuard-SCC"
    case volunteer = "LinkGuard-VO"
    case teamMember = "LinkGuard-TE"
    case teamLeader = "LinkGuard-TL"
    case emt = "LinkGuard-EMT"
    case sccIPad = "LinkGuard-SCC-iPad"
    case teamLeaderIPad = "LinkGuard-TL-iPad"
    case emtIPad = "LinkGuard-EMT-iPad"
}

public enum AppPlatform: String, Codable, Sendable {
    case mac
    case iPhone
    case iPad
}

public struct DeviceIdentity: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var appID: LinkGuardAppID
    public var platform: AppPlatform
    public var displayName: String

    public init(id: LinkGuardID, appID: LinkGuardAppID, platform: AppPlatform, displayName: String) {
        self.id = id
        self.appID = appID
        self.platform = platform
        self.displayName = displayName
    }
}
