import SwiftUI
import RelayCore

struct RelaySignInScreen: View {
    @State private var guide = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("RELAY").font(.system(size: 40, weight: .heavy)).padding(.top, 32)
                    Text("Connect with your shelter.").font(.title2.bold())
                    Text("Sign in with your RELAY account. Your account opens the resident or coordinator workspace.").foregroundStyle(RelayTheme.secondary)
                    AccountSignInView()
                    Text("An organizer provides demo accounts. Sign in once online; saved account setup and queued requests remain available when internet is lost.").font(.caption).foregroundStyle(RelayTheme.secondary)
                    Button("How RELAY works") { guide = true }.frame(minHeight: 44)
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(RelayTheme.canvas)
                .sheet(isPresented: $guide) { ResidentGuideView() }
        }
    }
}

struct SharedResidentSummary: View {
    let details: SharedResidentDetails
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shared personal details").font(.headline)
            Text("Provided by the requester · not independently verified").font(.caption).foregroundStyle(RelayTheme.secondary)
            WorkflowFact("Name", value: details.display_name)
            WorkflowFact("Preferred language", value: details.preferred_language)
            if let age = details.age { WorkflowFact("Age", value: "\(age) years") }
            if let height = details.height_cm { WorkflowFact("Height", value: "\(height.formatted()) cm") }
            if let weight = details.weight_kg { WorkflowFact("Weight", value: "\(weight.formatted()) kg") }
            if let blood = details.blood_group { WorkflowFact("Blood group", value: blood) }
            if let allergies = details.allergies { Text("Allergies: " + allergies) }
            if let conditions = details.health_conditions { Text("Health conditions: " + conditions) }
            if let medications = details.medications { Text("Medications: " + medications) }
            if let support = details.accessibility_needs { Text("Support needs: " + support) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
