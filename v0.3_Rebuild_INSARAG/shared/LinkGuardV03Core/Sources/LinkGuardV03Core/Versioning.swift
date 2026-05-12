import Foundation

public enum ReleaseChannel: String, Codable, CaseIterable, Sendable {
    case alpha
    case beta
    case releaseCandidate
    case stable
}

public struct SemanticVersion: Codable, Hashable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    public var prereleaseIdentifiers: [String]

    public init(major: Int, minor: Int, patch: Int, prereleaseIdentifiers: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prereleaseIdentifiers
    }

    public init?(string: String) {
        let parts = string.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        let core = parts.first?.split(separator: ".", omittingEmptySubsequences: false) ?? []
        guard core.count == 3,
              let major = Int(core[0]),
              let minor = Int(core[1]),
              let patch = Int(core[2]) else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        if parts.count == 2 {
            self.prereleaseIdentifiers = parts[1].split(separator: ".").map(String.init)
        } else {
            self.prereleaseIdentifiers = []
        }
    }

    public var stringValue: String {
        let core = "\(major).\(minor).\(patch)"
        guard prereleaseIdentifiers.isEmpty == false else { return core }
        return "\(core)-\(prereleaseIdentifiers.joined(separator: "."))"
    }

    public var description: String { stringValue }
}

public struct LinkGuardVersionInfo: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var product: String
    public var version: SemanticVersion
    public var shortVersion: String
    public var buildNumber: Int
    public var releaseChannel: ReleaseChannel
    public var gitTag: String
    public var series: String
    public var notes: String

    public init(
        schemaVersion: Int,
        product: String,
        version: SemanticVersion,
        shortVersion: String,
        buildNumber: Int,
        releaseChannel: ReleaseChannel,
        gitTag: String,
        series: String,
        notes: String
    ) {
        self.schemaVersion = schemaVersion
        self.product = product
        self.version = version
        self.shortVersion = shortVersion
        self.buildNumber = buildNumber
        self.releaseChannel = releaseChannel
        self.gitTag = gitTag
        self.series = series
        self.notes = notes
    }

    public var displayVersion: String {
        "\(version.stringValue) (\(buildNumber))"
    }

    public static let current = LinkGuardVersionInfo(
        schemaVersion: 1,
        product: "LinkGuard",
        version: SemanticVersion(major: 0, minor: 3, patch: 0, prereleaseIdentifiers: ["alpha", "1"]),
        shortVersion: "0.3.0",
        buildNumber: 300001,
        releaseChannel: .alpha,
        gitTag: "v0.3.0-alpha.1",
        series: "v0.3_Rebuild_INSARAG",
        notes: "First v0.3 shared app logic and transport-chain version baseline."
    )
}
