import Foundation

public struct CloudAnnouncement: Codable, Identifiable, Equatable {
    public let announcement_id: String
    public let incident_id: String
    public let shelter_id: String
    public let title: String
    public let text: String
    public let severity: String
    public let publisher: String
    public let created_at: Date
    public let updated_at: Date
    public let expires_at: Date
    public let revision: Int
    public let withdrawn: Bool
    public var id: String { announcement_id }
    public func active(at now: Date = Date()) -> Bool { !withdrawn && expires_at > now }
    public var spokenText: String { "\(severity.capitalized) announcement. \(title). From \(publisher). \(text)" }
}

public struct AnnouncementFeed: Codable {
    public let items: [CloudAnnouncement]
    public let fetched_at: Date
}

public struct AnnouncementCommand: Codable, Equatable {
    public let announcement_id: String
    public let shelter_id: String
    public let title: String
    public let text: String
    public let severity: String
    public let expires_at: Date
    public init(shelterID: String, title: String, text: String, severity: String, expiresAt: Date) throws {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !self.title.isEmpty, self.title.count <= 100, !self.text.isEmpty, self.text.count <= 1500,
              ["info", "important", "urgent"].contains(severity), !shelterID.isEmpty else { throw RelayError.invalid("Enter an announcement title and text (up to 1,500 characters), and choose a shelter.") }
        announcement_id = UUID().uuidString.lowercased(); shelter_id = shelterID
        self.severity = severity; expires_at = WireCodec.second(expiresAt)
    }
}

public struct ShelterDetails: Codable, Equatable {
    public let address: String
    public let instructions: String
    public let latitude: Double?
    public let longitude: Double?
    public let revision: Int
    public let updated_at: Date
    /// A geometric distance, never a route, travel time or assertion of safe access.
    public func distance(from location: RequestLocation) -> Double? {
        guard let latitude, let longitude, (-90...90).contains(latitude), (-180...180).contains(longitude),
              (try? location.validate()) != nil else { return nil }
        let radians = Double.pi / 180
        let dlat = (latitude - location.latitude) * radians
        let dlon = (longitude - location.longitude) * radians
        let a = pow(sin(dlat / 2), 2) + cos(location.latitude * radians) * cos(latitude * radians) * pow(sin(dlon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}

public struct ShelterDetailsCommand: Codable {
    public let expected_revision: Int
    public let address: String
    public let instructions: String
    public let latitude: Double?
    public let longitude: Double?
    public init(revision: Int, address: String, instructions: String, latitude: String, longitude: String) throws {
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        self.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        expected_revision = revision
        let lat = latitude.trimmingCharacters(in: .whitespacesAndNewlines), lon = longitude.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.address.count <= 240, self.instructions.count <= 1500, lat.isEmpty == lon.isEmpty else { throw RelayError.invalid("Enter both coordinates or leave both blank. Keep instructions under 1,500 characters.") }
        if lat.isEmpty { self.latitude = nil; self.longitude = nil }
        else {
            guard let a = Double(lat), let b = Double(lon), a.isFinite, b.isFinite,
                  (-90...90).contains(a), (-180...180).contains(b) else { throw RelayError.invalid("Check latitude (−90 to 90) and longitude (−180 to 180).") }
            self.latitude = a; self.longitude = b
        }
    }
}

public extension RelayStore {
    func announcementFeed(scope: String) throws -> AnnouncementFeed? {
        try setting("announcement_feed:" + scope).map { try CloudCodec.decode(AnnouncementFeed.self, Data($0.utf8)) }
    }
    func saveAnnouncementFeed(_ feed: AnnouncementFeed, scope: String) throws {
        try setSetting("announcement_feed:" + scope, String(decoding: CloudCodec.encode(feed), as: UTF8.self))
    }
}
