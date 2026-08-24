import AppIntents
import SwiftUI
import WidgetKit

/// A Control Centre button, and a Lock Screen / Action Button target, that opens the rental form.
///
/// The one thing worth reaching in a hurry. Somebody standing at a yard with a machine being
/// dropped off has both hands full and a phone in one of them; the useful thing at that moment is
/// not a dashboard, it is the form.
///
/// It opens the app and stops there. It does not create a rental — a record this app writes is
/// always something the user typed and saved, and a control that silently added a row would be a
/// record nobody chose to make.
struct OffRentQuickAddControl: ControlWidget {

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SharedIdentifiers.quickAddControlKind) {
            ControlWidgetButton(action: OpenAddRentalControlIntent()) {
                Label("Add rental", systemImage: "plus.rectangle.on.rectangle")
            }
        }
        .displayName("Add a rental")
        .description("Opens \(SharedBranding.displayName) on the new rental form.")
    }
}

/// Opens the app at the deep link the notifications and Shortcuts already use.
///
/// Declared here rather than shared with the app target because it does nothing but open a URL —
/// the app's own `AddRentalIntent` lives in the app binary, and reaching it from an extension
/// would mean compiling app code into the widget for no benefit.
struct OpenAddRentalControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a rental"
    static var description = IntentDescription(
        "Opens the new rental form. It does not create anything on its own."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DeepLink.addRental.url ?? URL(string: "offrent://")!))
    }
}
