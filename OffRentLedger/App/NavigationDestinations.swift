import SwiftUI

/// Registers every navigation destination on a tab's root.
///
/// SwiftUI resolves `NavigationLink(value:)` against the `navigationDestination` declarations in
/// the *enclosing* stack. Today links to a rental item and to an invoice; the invoice review links
/// back to a rental. Declaring destinations per-tab meant three of those links pushed a value the
/// surrounding stack had no handler for, which SwiftUI reports at runtime as a link that does
/// nothing — a dead tap, not a crash, and therefore the kind of bug that ships.
///
/// One modifier, applied at every tab root, removes the whole class of it: whichever stack a link
/// happens to be in, the destination is declared.
struct OffRentNavigationDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: RentalDestination.self) { destination in
                switch destination {
                case let .item(id): RentalItemDetailView(itemID: id)
                case let .agreement(id): AgreementDetailView(agreementID: id)
                case let .timeline(itemID): RentalTimelineView(itemID: itemID)
                case .vendors: VendorListView()
                case .jobSites: JobSiteListView()
                }
            }
            .navigationDestination(for: AuditDestination.self) { destination in
                switch destination {
                case let .invoice(id): InvoiceReviewView(invoiceID: id)
                case .followUps, .resolvedHistory: AuditView()
                }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .subscription: SubscriptionSettingsView()
                case .reminders: ReminderSettingsView()
                case .appearance: AppearanceSettingsView()
                case .dataAndPrivacy: DataAndPrivacyView()
                case .backupAndTransfer: BackupAndTransferView()
                case .privacyPolicy: LegalDocumentView(document: .privacy)
                case .terms: LegalDocumentView(document: .terms)
                case .support: SupportView()
                case .about: AboutView()
                }
            }
    }
}

extension View {
    func offRentNavigationDestinations() -> some View {
        modifier(OffRentNavigationDestinations())
    }
}
