import Foundation

/// A local, self-reported profile. Intentionally not part of any request or wire model.
public struct ResidentDetails: Codable, Equatable {
    public var name = ""
    public var age: Int?
    public var heightCM: Double?
    public var weightKG: Double?
    public var bloodGroup = ""
    public var allergies = ""
    public var healthConditions = ""
    public var medications = ""
    public var accessibilityNeeds = ""
    public var preferredLanguage: String?
    public var photoJPEG: Data?
    public init() {}
    public static let bloodGroups = ["", "A+", "A−", "B+", "B−", "AB+", "AB−", "O+", "O−"]
    public static let languages = ["English", "Spanish", "Mandarin", "Vietnamese", "Hindi", "Telugu", "Other"]
    public var isEmpty: Bool { name.isEmpty && age == nil && heightCM == nil && weightKG == nil && bloodGroup.isEmpty && allergies.isEmpty && healthConditions.isEmpty && medications.isEmpty && accessibilityNeeds.isEmpty && preferredLanguage == nil && photoJPEG == nil }
}

public struct ResidentDetailsDraft: Equatable {
    public var name: String
    public var age: String
    public var height: String
    public var weight: String
    public var bloodGroup: String
    public var allergies: String
    public var healthConditions: String
    public var medications: String
    public var accessibilityNeeds: String
    public var preferredLanguage: String
    public var photoJPEG: Data?
    public init(_ value: ResidentDetails = ResidentDetails()) {
        name = value.name; age = value.age.map(String.init) ?? ""
        height = value.heightCM.map { String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
        weight = value.weightKG.map { String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
        bloodGroup = value.bloodGroup; allergies = value.allergies; healthConditions = value.healthConditions
        medications = value.medications; accessibilityNeeds = value.accessibilityNeeds
        preferredLanguage = value.preferredLanguage ?? ""; photoJPEG = value.photoJPEG
    }
    public func validated(decimalSeparator: String = Locale.current.decimalSeparator ?? ".", requireBasics: Bool = false) throws -> ResidentDetails {
        func text(_ value: String, limit: Int, title: String) throws -> String {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.count <= limit else { throw RelayError.invalid("Keep \(title) under \(limit) characters.") }; return clean
        }
        func number(_ value: String, limit: Double, title: String) throws -> Double? {
            var clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { return nil }
            if decimalSeparator == "," { clean = clean.replacingOccurrences(of: ",", with: ".") }
            guard clean.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  let n = Double(clean), n.isFinite, n > 0, n <= limit else { throw RelayError.invalid("Enter \(title) as a number greater than zero, up to \(Int(limit)), or leave it blank.") }
            return n
        }
        var result = ResidentDetails()
        result.name = try text(name, limit: 80, title: "your name")
        guard !requireBasics || (!result.name.isEmpty && !preferredLanguage.isEmpty) else { throw RelayError.invalid("Enter a display name and choose your preferred language to save your profile.") }
        guard preferredLanguage.isEmpty || ResidentDetails.languages.contains(preferredLanguage) else { throw RelayError.invalid("Choose a preferred language.") }
        result.preferredLanguage = preferredLanguage.isEmpty ? nil : preferredLanguage
        if let photoJPEG {
            guard photoJPEG.count <= 24_000, photoJPEG.starts(with: [0xff, 0xd8]) else { throw RelayError.invalid("Choose a smaller profile photo.") }
            result.photoJPEG = photoJPEG
        }
        let years = age.trimmingCharacters(in: .whitespacesAndNewlines)
        if !years.isEmpty {
            guard years.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(years), (0...130).contains(value) else { throw RelayError.invalid("Age must be a whole number from 0 to 130, or blank.") }
            result.age = value
        }
        result.heightCM = try number(height, limit: 300, title: "height in cm")
        result.weightKG = try number(weight, limit: 1000, title: "weight in kg")
        guard ResidentDetails.bloodGroups.contains(bloodGroup) else { throw RelayError.invalid("Choose a blood group, or Not sure.") }
        result.bloodGroup = bloodGroup
        result.allergies = try text(allergies, limit: 400, title: "allergies")
        result.healthConditions = try text(healthConditions, limit: 500, title: "health conditions")
        result.medications = try text(medications, limit: 400, title: "medications")
        result.accessibilityNeeds = try text(accessibilityNeeds, limit: 400, title: "accessibility needs")
        return result
    }
}

/// These flags contain no personal details and are safe to keep in the existing metadata store.
public struct ResidentSetupState: Codable, Equatable {
    public var profileOffered = false
    public var guideSeen = false
    public init() {}
    public var needsWelcome: Bool { !profileOffered || !guideSeen }
}

public extension RelayStore {
    func residentSetup(scope: String) throws -> ResidentSetupState {
        try setting("resident_setup_v1:" + scope).map { try CloudCodec.decode(ResidentSetupState.self, Data($0.utf8)) } ?? ResidentSetupState()
    }
    func saveResidentSetup(_ value: ResidentSetupState, scope: String) throws {
        try setSetting("resident_setup_v1:" + scope, String(decoding: CloudCodec.encode(value), as: UTF8.self))
    }
}

public extension InventoryItem {
    static func emoji(_ id: String) -> String {
        switch id { case "water_packs": return "💧"; case "food_packs": return "🥫"; case "blankets": return "🛏️"; case "medicines": return "💊"; default: return "📦" }
    }
}
