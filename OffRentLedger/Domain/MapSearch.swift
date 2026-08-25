import Foundation

/// One thing that can appear on the operations map, flattened out of the store.
///
/// Deliberately not a second copy of anything. §1 of the brief is explicit that equipment lives
/// inside a rental rather than in its own table, so an equipment marker is *derived* from the
/// rental it belongs to and carries that rental's identifier. Nothing here is persisted.
struct MapRecord: Sendable, Equatable, Identifiable {

    enum Kind: String, Sendable, Equatable, CaseIterable {
        /// A saved jobsite. Drawn even when nothing is on rent there.
        case jobsite
        /// A rental — that is, a machine — placed at its jobsite's coordinate.
        case rental

        var displayName: String {
            switch self {
            case .jobsite: "Jobsite"
            case .rental: "Rental"
            }
        }

        var symbolName: String {
            switch self {
            case .jobsite: "mappin.and.ellipse"
            case .rental: "shippingbox.fill"
            }
        }
    }

    var id: UUID
    var kind: Kind
    var title: String
    /// Company for a rental, address for a jobsite.
    var subtitle: String?
    /// nil for a jobsite, which has no status of its own.
    var status: RentalItemStatus?
    var jobSiteID: UUID?
    var jobSiteName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    /// Everything the local search looks in, already flattened. Held rather than recomputed so a
    /// keystroke does not walk the object graph again.
    var searchTerms: [String]

    init(
        id: UUID,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        status: RentalItemStatus? = nil,
        jobSiteID: UUID? = nil,
        jobSiteName: String? = nil,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        searchTerms: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.jobSiteID = jobSiteID
        self.jobSiteName = jobSiteName
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.searchTerms = searchTerms
    }

    var hasCoordinate: Bool { latitude != nil && longitude != nil }

    /// What VoiceOver says. Never "pin": the brief requires the entity and its state.
    var accessibilityLabel: String {
        var parts: [String] = [kind.displayName, title]
        if let status { parts.append(status.displayName) }
        if let jobSiteName, kind == .rental { parts.append("at \(jobSiteName)") }
        if !hasCoordinate { parts.append("No location set") }
        return parts.joined(separator: ", ")
    }
}

/// Searching the user's own records — never the web.
enum MapSearch {

    /// Case- and diacritic-insensitive substring match across every term on the record.
    ///
    /// Every whitespace-separated word in the query must match something, so "skid ridgeline"
    /// finds the skid steer at Ridgeline and not every machine and every site separately. That
    /// is the behaviour people expect from a search field they are using to narrow, not to
    /// broaden.
    static func matches(_ records: [MapRecord], query: String) -> [MapRecord] {
        let words = tokenise(query)
        guard !words.isEmpty else { return records }
        return records.filter { record in
            let haystack = normalise(record.searchTerms.joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    static func tokenise(_ query: String) -> [String] {
        normalise(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    private static func normalise(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}

/// Records that share a coordinate, drawn as one marker.
struct MapCluster: Sendable, Equatable, Identifiable {
    var id: String
    var latitude: Double
    var longitude: Double
    var records: [MapRecord]

    var count: Int { records.count }

    /// What the cluster's list should offer to open.
    ///
    /// When rentals share a coordinate with their jobsite, the jobsite is the *place* — it is
    /// already the cluster's title — and listing it beside the machines on it is a row that says
    /// the same thing twice. A cluster with no rentals lists what it has, which is how a saved
    /// jobsite with nothing on rent stays reachable.
    var listedRecords: [MapRecord] {
        let rentals = records.filter { $0.kind == .rental }
        return rentals.isEmpty ? records : rentals
    }

    /// Whether tapping this marker should go straight to a detail card rather than a list.
    var isSingle: Bool { listedRecords.count == 1 }

    /// The record whose colour and symbol the marker takes. A jobsite loses to any rental on it,
    /// and among rentals the most urgent wins — a yard with one machine waiting on a phone call
    /// must not read as settled because the other three are.
    var representative: MapRecord? {
        records.min { lhs, rhs in rank(lhs) > rank(rhs) }
    }

    var title: String {
        guard let representative else { return "Location" }
        if isSingle { return representative.title }
        let rentals = records.filter { $0.kind == .rental }.count
        if rentals == 0 { return representative.title }
        let site = records.first { $0.kind == .jobsite }?.title
            ?? representative.jobSiteName
            ?? representative.title
        return site
    }

    var accessibilityLabel: String {
        guard !isSingle else { return representative?.accessibilityLabel ?? "Location" }
        let rentals = records.filter { $0.kind == .rental }
        let names = rentals.map(\.title).joined(separator: ", ")
        return rentals.isEmpty
            ? "\(title), \(count) records"
            : "\(title), \(rentals.count) rental\(rentals.count == 1 ? "" : "s"): \(names)"
    }

    private func rank(_ record: MapRecord) -> Int {
        guard record.kind == .rental else { return 0 }
        switch record.status {
        case .contactVendor, .needsFollowUp: return 5
        case .invoiceReview: return 4
        case .awaitingPickup, .confirmationRecorded, .pickedUp: return 3
        case .active, .draft: return 2
        default: return 1
        }
    }
}

enum MapClustering {

    /// Two records cluster when their coordinates round to the same five decimal places — about
    /// a metre. Anything closer than that is the same yard, and two markers on the same point
    /// are a stack the user cannot tap the bottom of.
    static let precision: Double = 100_000

    static func cluster(_ records: [MapRecord]) -> [MapCluster] {
        var grouped: [String: MapCluster] = [:]
        for record in records {
            guard let latitude = record.latitude, let longitude = record.longitude else { continue }
            let key = bucketKey(latitude: latitude, longitude: longitude)
            if grouped[key] == nil {
                grouped[key] = MapCluster(
                    id: key, latitude: latitude, longitude: longitude, records: []
                )
            }
            grouped[key]?.records.append(record)
        }
        return grouped.values.sorted { $0.title < $1.title }
    }

    /// Records with nowhere to be drawn. Listed rather than dropped: a rental with no location is
    /// the one the user most needs to find, and putting it at a made-up coordinate would be a lie
    /// the map tells silently.
    static func unplaced(_ records: [MapRecord]) -> [MapRecord] {
        records.filter { !$0.hasCoordinate }
    }

    static func bucketKey(latitude: Double, longitude: Double) -> String {
        let lat = (latitude * precision).rounded() / precision
        let lon = (longitude * precision).rounded() / precision
        return "\(lat),\(lon)"
    }
}

/// The filter chips above the operations map.
enum MapFilter: String, CaseIterable, Sendable, Identifiable {
    case all
    case onRent
    case awaitingPickup
    case closed
    case jobsites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .onRent: "On rent"
        case .awaitingPickup: "Awaiting pickup"
        case .closed: "Closed"
        case .jobsites: "Jobsites"
        }
    }

    func allows(_ record: MapRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .jobsites:
            return record.kind == .jobsite
        case .onRent:
            guard let status = record.status else { return false }
            return status == .active || status == .draft || status == .contactVendor
        case .awaitingPickup:
            guard let status = record.status else { return false }
            return status == .confirmationRecorded || status == .awaitingPickup
                || status == .pickedUp
        case .closed:
            guard let status = record.status else { return false }
            return status == .resolved || status == .archived
        }
    }

    static func apply(_ filter: MapFilter, to records: [MapRecord]) -> [MapRecord] {
        records.filter(filter.allows)
    }
}
