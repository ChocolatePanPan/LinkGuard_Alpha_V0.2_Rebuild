import Foundation

public enum AccountStatus: String, Codable, CaseIterable, Sendable {
    case active
    case suspended
    case revoked
}

public enum AccountAccessError: Error, Equatable, Sendable {
    case accountNotFound(LinkGuardID)
    case ambiguousIdentifier(String)
    case invalidCredential(LinkGuardID)
    case inactiveAccount(LinkGuardID)
    case appNotAllowed(accountID: LinkGuardID, appID: LinkGuardAppID)
    case sessionNotFound(LinkGuardID)
    case sessionExpired(LinkGuardID)
    case permissionDenied(sessionID: LinkGuardID, permission: LinkGuardPermission)
}

public struct UserAccount: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var personID: LinkGuardID
    public var displayName: String
    public var callSign: String?
    public var status: AccountStatus
    public var allowedAppIDs: Set<LinkGuardAppID>
    public var defaultPosition: ICSPosition
    public var credentialDigest: String
    public var extraPermissions: Set<LinkGuardPermission>
    public var revokedPermissions: Set<LinkGuardPermission>

    public init(
        id: LinkGuardID,
        personID: LinkGuardID,
        displayName: String,
        callSign: String? = nil,
        status: AccountStatus = .active,
        allowedAppIDs: Set<LinkGuardAppID>,
        defaultPosition: ICSPosition,
        credentialDigest: String,
        extraPermissions: Set<LinkGuardPermission> = [],
        revokedPermissions: Set<LinkGuardPermission> = []
    ) {
        self.id = id
        self.personID = personID
        self.displayName = displayName
        self.callSign = callSign
        self.status = status
        self.allowedAppIDs = allowedAppIDs
        self.defaultPosition = defaultPosition
        self.credentialDigest = credentialDigest
        self.extraPermissions = extraPermissions
        self.revokedPermissions = revokedPermissions
    }

    public func canUse(appID: LinkGuardAppID) -> Bool {
        allowedAppIDs.isEmpty || allowedAppIDs.contains(appID)
    }
}

public struct LoginSession: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var accountID: LinkGuardID
    public var personID: LinkGuardID
    public var displayName: String
    public var device: DeviceIdentity
    public var position: ICSPosition
    public var profile: RoleProfile
    public var issuedAt: Date
    public var expiresAt: Date?
    public var permissions: Set<LinkGuardPermission>

    public init(
        id: LinkGuardID,
        accountID: LinkGuardID,
        personID: LinkGuardID,
        displayName: String,
        device: DeviceIdentity,
        position: ICSPosition,
        profile: RoleProfile,
        issuedAt: Date,
        expiresAt: Date? = nil,
        permissions: Set<LinkGuardPermission>
    ) {
        self.id = id
        self.accountID = accountID
        self.personID = personID
        self.displayName = displayName
        self.device = device
        self.position = position
        self.profile = profile
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.permissions = permissions
    }

    public func isActive(at date: Date) -> Bool {
        if let expiresAt, expiresAt <= date { return false }
        return true
    }

    public func allows(_ permission: LinkGuardPermission, at date: Date) -> Bool {
        isActive(at: date) && permissions.contains(permission)
    }
}

public struct AccountDirectory: Codable, Sendable {
    public private(set) var accounts: [LinkGuardID: UserAccount]
    public private(set) var sessions: [LinkGuardID: LoginSession]

    public init(accounts: [UserAccount] = [], sessions: [LoginSession] = []) {
        self.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        self.sessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    public mutating func upsert(_ account: UserAccount) {
        accounts[account.id] = account
    }

    public func account(for identifier: String) throws -> UserAccount {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = accounts.values.filter { account in
            if account.id.rawValue == normalized { return true }
            if account.personID.rawValue == normalized { return true }
            if account.callSign?.caseInsensitiveCompare(normalized) == .orderedSame { return true }
            return false
        }

        guard let account = matches.first else {
            throw AccountAccessError.accountNotFound(LinkGuardID(normalized))
        }
        guard matches.count == 1 else {
            throw AccountAccessError.ambiguousIdentifier(normalized)
        }
        return account
    }

    @discardableResult
    public mutating func login(
        accountID: LinkGuardID,
        credentialDigest: String,
        device: DeviceIdentity,
        issuedAt: Date,
        expiresAt: Date? = nil,
        sessionID: LinkGuardID = .generated(prefix: "SESSION")
    ) throws -> LoginSession {
        guard let account = accounts[accountID] else {
            throw AccountAccessError.accountNotFound(accountID)
        }
        guard account.status == .active else {
            throw AccountAccessError.inactiveAccount(accountID)
        }
        guard account.credentialDigest == credentialDigest else {
            throw AccountAccessError.invalidCredential(accountID)
        }
        guard account.canUse(appID: device.appID) else {
            throw AccountAccessError.appNotAllowed(accountID: accountID, appID: device.appID)
        }

        let profile = RoleProfileCatalog.profile(for: device.appID)
        var permissions = profile.permissions
        permissions.formUnion(account.extraPermissions)
        permissions.subtract(account.revokedPermissions)
        let session = LoginSession(
            id: sessionID,
            accountID: account.id,
            personID: account.personID,
            displayName: account.displayName,
            device: device,
            position: account.defaultPosition,
            profile: profile,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            permissions: permissions
        )
        sessions[session.id] = session
        return session
    }

    @discardableResult
    public mutating func login(
        identifier: String,
        credentialDigest: String,
        device: DeviceIdentity,
        issuedAt: Date,
        expiresAt: Date? = nil,
        sessionID: LinkGuardID = .generated(prefix: "SESSION")
    ) throws -> LoginSession {
        let account = try account(for: identifier)
        return try login(
            accountID: account.id,
            credentialDigest: credentialDigest,
            device: device,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            sessionID: sessionID
        )
    }

    public mutating func logout(sessionID: LinkGuardID) {
        sessions.removeValue(forKey: sessionID)
    }

    public func authorize(sessionID: LinkGuardID, permission: LinkGuardPermission, at date: Date) throws {
        guard let session = sessions[sessionID] else {
            throw AccountAccessError.sessionNotFound(sessionID)
        }
        guard session.isActive(at: date) else {
            throw AccountAccessError.sessionExpired(sessionID)
        }
        guard session.permissions.contains(permission) else {
            throw AccountAccessError.permissionDenied(sessionID: sessionID, permission: permission)
        }
    }
}