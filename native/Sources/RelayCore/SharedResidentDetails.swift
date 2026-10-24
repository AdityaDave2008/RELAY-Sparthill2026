import Foundation

/// Explicit per-request snapshot. Local avatar and account credentials are never included.
public struct SharedResidentDetails: Codable, Equatable {
    public let display_name: String
    public let preferred_language: String
    public let age: Int?
    public let height_cm: Double?
    public let weight_kg: Double?
    public let blood_group: String?
    public let allergies: String?
    public let health_conditions: String?
    public let medications: String?
    public let accessibility_needs: String?
    public init(profile: ResidentDetails, includeHealth: Bool, includeSupport: Bool) throws {
        let value = try ResidentDetailsDraft(profile).validated(decimalSeparator: ".", requireBasics: true)
        display_name = value.name; preferred_language = value.preferredLanguage!
        age = includeHealth ? value.age : nil; height_cm = includeHealth ? value.heightCM : nil; weight_kg = includeHealth ? value.weightKG : nil
        func included(_ text: String, _ enabled: Bool) -> String? { enabled && !text.isEmpty ? text : nil }
        blood_group = included(value.bloodGroup, includeHealth); allergies = included(value.allergies, includeHealth)
        health_conditions = included(value.healthConditions, includeHealth); medications = included(value.medications, includeHealth)
        accessibility_needs = included(value.accessibilityNeeds, includeSupport)
        try validate()
    }
    public func validate() throws {
        var value = ResidentDetails()
        value.name = display_name; value.preferredLanguage = preferred_language
        value.age = age; value.heightCM = height_cm; value.weightKG = weight_kg; value.bloodGroup = blood_group ?? ""
        value.allergies = allergies ?? ""; value.healthConditions = health_conditions ?? ""; value.medications = medications ?? ""; value.accessibilityNeeds = accessibility_needs ?? ""
        _ = try ResidentDetailsDraft(value).validated(decimalSeparator: ".", requireBasics: true)
        guard try CloudCodec.encode(self).count <= 4096 else { throw RelayError.invalid("Shorten the personal notes before sharing them with this request.") }
    }
}
