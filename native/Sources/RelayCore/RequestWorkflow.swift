import Foundation

public struct RequestLocation: Codable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let horizontal_accuracy: Double
    public let captured_at: Date
    public let precision: String
    public let source: String
    public init(latitude: Double, longitude: Double, accuracy: Double, capturedAt: Date = Date(), precision: String = "precise", source: String = "device") throws {
        self.latitude = latitude; self.longitude = longitude; horizontal_accuracy = accuracy
        captured_at = WireCodec.second(capturedAt); self.precision = precision; self.source = source
        try validate()
    }
    public func validate() throws {
        guard latitude.isFinite, longitude.isFinite, horizontal_accuracy.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude), (0...100_000).contains(horizontal_accuracy),
              ["precise", "approximate"].contains(precision), ["device", "manual"].contains(source) else { throw RelayError.invalid("Location is invalid. Retry or enter a landmark.") }
    }
}
public struct RequestFields: Codable, Equatable {
    public var item_id: String?
    public var quantity: Int?
    public var unit: String?
    public var people: Int?
    public var landmark: String
    public var urgency: String?
    public var medicine_details: String?
    public init(item: String?, quantity: Int?, unit: String?, people: Int?, landmark: String, urgency: String? = nil, medicineDetails: String? = nil) {
        item_id = item; self.quantity = quantity; self.unit = unit; self.people = people; self.landmark = landmark; self.urgency = urgency; medicine_details = medicineDetails
    }
}
public struct RequestDraft: Codable, Equatable {
    public var id = UUID().uuidString.lowercased()
    public var shelterID = ""
    public var text = ""
    public var item = "other"
    public var quantity = ""
    public var people = ""
    public var landmark = ""
    public var urgency: String?
    public var medicineDetails: String?
    public var requestedUnit: String?
    public var location: RequestLocation?
    public var requesterDetails: SharedResidentDetails?
    public var transcriptionID: String?
    public var interpretationReady: Bool?
    public var interpretationID: String?
    public var interpretationText: String?
    public var interpretationShelter: String?
    public var interpretationTranscription: String?
    public init() {}
    public static let units = ["pack", "piece", "bottle", "item", "tablet", "vial", "box"]
    /// Enforced by the current composer, without invalidating historical queued messages.
    public func validateLocationForNewRequest() throws {
        if let location { try location.validate() }
        else if landmark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RelayError.invalid("Add your location or type an address, landmark or room so shelter staff know where you are.")
        }
    }
    public var unit: String { requestedUnit ?? (item == "blankets" ? "piece" : item == "medicines" ? "item" : "pack") }
    public func fields() throws -> RequestFields {
        func count(_ s: String, limit: Int) throws -> Int? {
            let s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { return nil }
            guard let value = Int(s), (1...limit).contains(value) else { throw RelayError.invalid("Enter a positive whole number, or leave unknown amounts blank.") }
            return value
        }
        guard ["water_packs", "food_packs", "blankets", "medicines", "other"].contains(item), landmark.count <= 240, Self.units.contains(unit), urgency == nil || RequestUrgency(rawValue: urgency!) != nil, (medicineDetails?.count ?? 0) <= 240 else { throw RelayError.invalid("Check the item and landmark.") }
        let amount = try count(quantity, limit: 10000)
        return RequestFields(item: item, quantity: amount, unit: amount == nil ? nil : unit, people: try count(people, limit: 1_000_000), landmark: landmark, urgency: urgency, medicineDetails: item == "medicines" ? medicineDetails : nil)
    }
}
public struct InterpretationCommand: Codable, Equatable {
    public let operation_id: String
    public let interpretation_id: String
    public let incident_id: String
    public let destination_shelter_id: String
    public let original_text: String
    public let transcription_id: String?
    public init(id: String, incident: String, shelter: String, text: String, transcription: String?) {
        operation_id = id; interpretation_id = id; incident_id = incident; destination_shelter_id = shelter
        original_text = text; transcription_id = transcription
    }
}
public struct InterpretationResult: Codable {
    public let interpretation_id: String
    public let status: String
    public let result: CloudValidatedResult?
    public let error: CloudErrorDetail?
}
public struct InventoryItem: Codable, Identifiable {
    public let item_id: String
    public let unit: String
    public let on_hand: Int
    public let reserved: Int
    public let available: Int
    public let revision: Int
    public var id: String { item_id }
    public var title: String { Self.title(item_id) }
    public static func title(_ id: String) -> String {
        switch id { case "water_packs": return "Water packs"; case "food_packs": return "Food packs"; case "blankets": return "Blankets"; case "medicines": return "Medicines"; default: return "Other" }
    }
}
public struct InventorySnapshot: Codable { public let shelter_id: String; public let items: [InventoryItem] }
public struct InventoryAdjustment: Codable {
    public let operation_id: String
    public let item_id: String
    public let quantity_delta: Int
    public let expected_revision: Int
    public let note: String
    public init(id: String = UUID().uuidString.lowercased(), item: String, delta: Int, revision: Int, note: String) {
        operation_id = id; item_id = item; quantity_delta = delta; expected_revision = revision; self.note = note
    }
}
public struct RequestReservation: Codable {
    public let item_id: String
    public let quantity: Int
    public let unit: String
    public let status: String
}
public struct ReservationResult: Codable {
    public let request_id: String
    public let reservation: RequestReservation?
    public let history: CloudHistory?
}
public struct InventoryCommand: Codable, Equatable {
    public let operation_id: String
    public let action: String
    public let item_id: String?
    public let quantity: Int?
    public let expected_inventory_revision: Int?
    public init(action: String, item: String? = nil, quantity: Int? = nil, revision: Int? = nil) {
        operation_id = UUID().uuidString.lowercased(); self.action = action; item_id = item
        self.quantity = quantity; expected_inventory_revision = revision
    }
}

public enum RequestUrgency: String, Codable, CaseIterable {
    case routine, soon, urgent, immediate
    public var title: String { rawValue.capitalized }
    public var explanation: String {
        switch self {
        case .routine: return "No time pressure stated"
        case .soon: return "Needed soon"
        case .urgent: return "Time-sensitive request"
        case .immediate: return "Help requested right now"
        }
    }
}

public enum ExtractionReview {
    public static func message(_ code: String) -> String {
        switch code {
        case "invalid_model_output": return "Details could not be extracted. Your text is saved; enter the fields yourself."
        case "missing_quantity", "quantity_not_grounded": return "Confirm the supply quantity, or leave it unknown. People counts are separate."
        case "multiple_quantities_require_review": return "More than one supply quantity was mentioned. Confirm the amount below."
        case "multiple_items_require_review": return "Several supplies were mentioned. This request holds one type; create another request for the others."
        case "negation_requires_review": return "The request may include a cancellation or correction. Check before sending."
        case "unit_mismatch", "unit_not_grounded", "missing_unit": return "Confirm the requested unit. Staff must check it against their stock units."
        case "medicine_staff_review": return "Medicine requests need staff review. No medicine or dose is recommended automatically."
        case "urgency_not_grounded": return "Urgency was not clearly stated. Choose a tag yourself if needed."
        case "people_not_grounded": return "Confirm how many people need help."
        case "landmark_not_grounded": return "Enter a landmark or attach your location."
        case "complex_quantity_requires_review", "unsupported_quantity_format": return "Check the amount; it may be approximate, fractional or phrased ambiguously."
        case "shelter_mismatch", "text_destination_conflict", "missing_shelter": return "The spoken shelter may differ from your selection. Check the destination."
        case "unknown_or_missing_item", "item_not_grounded", "missing_item": return "Choose the supply type that matches your request."
        default: return "Check this detail: " + code.replacingOccurrences(of: "_", with: " ")
        }
    }
}
