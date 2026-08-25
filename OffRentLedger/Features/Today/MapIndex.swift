import Foundation
import SwiftData

/// Flattens the store into the records the maps draw and search.
///
/// One builder, used by the Today card and by the full-screen operations map, so the two cannot
/// disagree about what is on the map. It produces value types with no reference back into
/// SwiftData: a `MapRecord` can be filtered, sorted and searched on a keystroke without touching
/// a model object, which is what keeps typing in the search field smooth.
///
/// Equipment is *derived*, never duplicated. A machine has no table of its own — it is a
/// `RentalItem` — so its marker carries that rental's identifier and opening it opens the rental.
/// What the two map screens compare to decide whether their cached index is stale.
struct MapIndexKey: Hashable {
    var items: Int
    var jobSites: Int
    var latestChange: TimeInterval
}

enum MapIndex {

    /// Every jobsite and every rental, whether or not it has somewhere to be drawn.
    ///
    /// Records with no coordinate are included on purpose. They cannot be pinned, but they are
    /// findable by search and the detail card offers to give them a location — which is the only
    /// way somebody discovers that a rental is missing from the map at all.
    static func build(items: [RentalItem], jobSites: [JobSite]) -> [MapRecord] {
        var records: [MapRecord] = []
        records.reserveCapacity(items.count + jobSites.count)

        for site in jobSites {
            let coordinate = site.coordinate
            var terms: [String] = [site.name]
            if let placeName = site.placeName { terms.append(placeName) }
            if let address = site.address { terms.append(address) }
            if let project = site.projectIdentifier { terms.append(project) }

            records.append(
                MapRecord(
                    id: site.id,
                    kind: .jobsite,
                    title: site.name,
                    subtitle: site.locationSummary,
                    jobSiteID: site.id,
                    jobSiteName: site.name,
                    address: site.address ?? site.placeName,
                    latitude: coordinate?.latitude,
                    longitude: coordinate?.longitude,
                    searchTerms: terms
                )
            )
        }

        for item in items {
            let agreement = item.agreement
            let site = agreement?.jobSite
            let coordinate = site?.coordinate

            // Spelled out as an annotated local. A `[String?]` literal with nine entries, some
            // `String` and some `String?`, is the shape the type checker gives up on.
            let optionalTerms: [String?] = [
                item.equipmentName,
                item.equipmentClass,
                item.vendorEquipmentIdentifier,
                item.serialNumber,
                agreement?.agreementNumber,
                agreement?.purchaseOrderNumber,
                agreement?.vendor?.name,
                agreement?.vendor?.branch,
                site?.name,
                site?.address,
                site?.placeName,
                item.status.displayName,
            ]

            records.append(
                MapRecord(
                    id: item.id,
                    kind: .rental,
                    title: item.equipmentName,
                    subtitle: agreement?.vendor?.name,
                    status: item.status,
                    jobSiteID: site?.id,
                    jobSiteName: site?.name,
                    address: site?.address ?? site?.placeName,
                    latitude: coordinate?.latitude,
                    longitude: coordinate?.longitude,
                    searchTerms: optionalTerms.compactMap { $0 }
                )
            )
        }

        return records
    }

    /// Records worth drawing on the Today card: open rentals, plus the jobsites they are at.
    ///
    /// Closed and archived rentals are deliberately left off Today — that screen is about what
    /// needs doing — but they remain on the operations map, which is about where everything is.
    static func todayRecords(_ all: [MapRecord]) -> [MapRecord] {
        let openSiteIDs = Set(
            all.compactMap { record -> UUID? in
                guard record.kind == .rental, record.status?.isOpen == true else { return nil }
                return record.jobSiteID
            }
        )
        return all.filter { record in
            switch record.kind {
            case .rental: return record.status?.isOpen == true
            case .jobsite: return record.jobSiteID.map(openSiteIDs.contains) ?? false
            }
        }
    }
}
