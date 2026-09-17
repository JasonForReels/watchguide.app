//
//  TicketStubStore.swift
//  WatchGuide-MovieandTVtracker
//
//  Every finished watch tears off a ticket stub: the title plus the details a
//  real stub would have (date, seat, who you went with, a one-word verdict).
//  Stubs are also written to the regular Watched list so the rest of the app
//  and sync stay in step.
//

import Foundation
import SwiftUI

struct TicketStub: Identifiable, Codable, Hashable {
    enum Verdict: String, Codable, CaseIterable, Identifiable {
        case loved, liked, meh, walkedOut
        var id: String { rawValue }
        var label: String {
            switch self {
            case .loved: return "Loved It"
            case .liked: return "Liked It"
            case .meh: return "It Was Okay"
            case .walkedOut: return "Didn’t Finish"
            }
        }
        var symbol: String {
            switch self {
            case .loved: return "heart.fill"
            case .liked: return "hand.thumbsup.fill"
            case .meh: return "hand.thumbsdown"
            case .walkedOut: return "stop.circle"
            }
        }
    }

    let id: UUID
    let mediaId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?
    let year: String?
    let watchedAt: Date
    var verdict: Verdict
    var company: String
    var note: String

    /// Deterministic "seat" printed on the stub, e.g. "ROW F · SEAT 12".
    var seat: String {
        let rows = Array("ABCDEFGHJKLM")
        let h = abs(mediaId &* 31 &+ Int(watchedAt.timeIntervalSince1970) / 86_400)
        return "ROW \(rows[h % rows.count]) · SEAT \(h % 24 + 1)"
    }

    /// Admit number, stable per stub.
    var admitNumber: String {
        String(format: "%06d", abs(id.hashValue) % 1_000_000)
    }
}

@MainActor
final class TicketStubStore: ObservableObject {
    static let shared = TicketStubStore()

    @Published private(set) var stubs: [TicketStub] = []

    private let key = "wg.ticketStubs.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TicketStub].self, from: data) {
            stubs = decoded
        }
    }

    func tear(for item: MediaItem, verdict: TicketStub.Verdict, company: String = "", note: String = "") {
        let stub = TicketStub(
            id: UUID(),
            mediaId: item.id,
            mediaType: item.resolvedMediaType,
            title: item.displayTitle,
            posterPath: item.posterPath,
            year: item.year,
            watchedAt: Date(),
            verdict: verdict,
            company: company,
            note: note
        )
        stubs.insert(stub, at: 0)
        persist()

        let storage = StorageService.shared
        if !storage.isInWatched(item.id, mediaType: item.resolvedMediaType) {
            storage.addToWatched(SavedMediaItem(from: item))
        }
        if verdict == .loved, !storage.isInLiked(item.id, mediaType: item.resolvedMediaType) {
            storage.addToLiked(SavedMediaItem(from: item))
        }
    }

    func remove(_ stub: TicketStub) {
        stubs.removeAll { $0.id == stub.id }
        persist()
    }

    /// Stubs grouped by month, newest first, for the stub box.
    var byMonth: [(month: String, stubs: [TicketStub])] {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        var order: [String] = []
        var groups: [String: [TicketStub]] = [:]
        for stub in stubs {
            let k = f.string(from: stub.watchedAt)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(stub)
        }
        return order.map { ($0, groups[$0]!) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stubs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
