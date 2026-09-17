//
//  SoundtrackSyncService.swift
//  WatchGuide-MovieandTVtracker
//
//  Watch-Along — the second sync signal. Dialogue can't lock on during
//  action or music-only scenes, but songs can: ShazamKit tells us which track
//  is playing *and* how many seconds into the track we are.
//
//  Shazam knows songs, not where a film uses them, so WatchGuide learns that
//  itself. Whenever a viewer is already dialogue-synced and a song is
//  recognised, we record "this song starts at 1:12:40 in this title" and
//  share it through the Supabase cache. From then on, anyone watching can
//  lock on from the soundtrack alone — even in a scene with no dialogue.
//
//  iOS-only.
//

#if os(iOS)
import Foundation
import AVFoundation
import ShazamKit

/// A recognised song and where we are inside it.
struct SoundtrackMatch: Equatable {
    let key: String
    let title: String
    let artist: String?
    let artworkURL: URL?
    /// Seconds into the song at the moment `matchedAt`.
    let songOffset: TimeInterval
    let matchedAt: Date
}

/// "This song starts at `titleTime` in this title." A song can be used more
/// than once, so a title keeps every start it has seen.
struct SoundtrackAnchor: Codable, Hashable {
    let songKey: String
    let songTitle: String
    var titleTimeAtSongStart: TimeInterval
    var confirmations: Int
}

// MARK: - Recogniser

/// Feeds microphone buffers to ShazamKit and reports matches on the main actor.
final class SoundtrackRecognizer: NSObject, SHSessionDelegate {
    private let session = SHSession()
    private let onMatch: @MainActor (SoundtrackMatch) -> Void

    init(onMatch: @escaping @MainActor (SoundtrackMatch) -> Void) {
        self.onMatch = onMatch
        super.init()
        session.delegate = self
    }

    /// Call from the audio tap with every buffer the microphone produces.
    func append(_ buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        session.matchStreamingBuffer(buffer, at: when)
    }

    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        let key = item.shazamID ?? item.isrc ?? "\(item.title ?? "")|\(item.artist ?? "")"
        guard !key.isEmpty, key != "|" else { return }
        let result = SoundtrackMatch(
            key: key,
            title: item.title ?? "Unknown song",
            artist: item.artist,
            artworkURL: item.artworkURL,
            songOffset: item.predictedCurrentMatchOffset,
            matchedAt: Date()
        )
        Task { @MainActor [onMatch] in onMatch(result) }
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {}
}

// MARK: - Anchor store

actor SoundtrackAnchorStore {
    static let shared = SoundtrackAnchorStore()

    private var cache: [String: [SoundtrackAnchor]] = [:]
    private init() {}

    static func titleKey(tmdbId: Int, season: Int?, episode: Int?) -> String {
        [tmdbId, season ?? -1, episode ?? -1].map(String.init).joined(separator: "_")
    }

    func anchors(for titleKey: String) async -> [SoundtrackAnchor] {
        if let cached = cache[titleKey] { return cached }
        var merged = loadLocal(titleKey)
        if let remote = await SupabaseCacheService.shared.get(key: remoteKey(titleKey), as: [SoundtrackAnchor].self) {
            merged = Self.merge(merged, remote)
        }
        cache[titleKey] = merged
        return merged
    }

    /// Records where a song started, learned while dialogue-synced.
    func learn(titleKey: String, match: SoundtrackMatch, titleTimeAtSongStart: TimeInterval) async {
        let learned = SoundtrackAnchor(songKey: match.key, songTitle: match.title, titleTimeAtSongStart: titleTimeAtSongStart, confirmations: 1)
        // Re-read the shared copy right before writing so concurrent viewers
        // don't erase each other's anchors.
        var current = loadLocal(titleKey)
        if let remote = await SupabaseCacheService.shared.get(key: remoteKey(titleKey), as: [SoundtrackAnchor].self) {
            current = Self.merge(current, remote)
        }
        let updated = Self.merge(current, [learned])
        cache[titleKey] = updated
        saveLocal(updated, titleKey)
        if let data = try? JSONEncoder().encode(updated) {
            await SupabaseCacheService.shared.set(key: remoteKey(titleKey), source: .watchalong, responseData: data, ttlSeconds: 60 * 60 * 24 * 365)
        }
    }

    /// Anchors within 20 s of each other for the same song are the same use of
    /// that song; they're averaged, weighted by how often each was confirmed.
    static func merge(_ lhs: [SoundtrackAnchor], _ rhs: [SoundtrackAnchor]) -> [SoundtrackAnchor] {
        var result = lhs
        for anchor in rhs {
            if let index = result.firstIndex(where: {
                $0.songKey == anchor.songKey && abs($0.titleTimeAtSongStart - anchor.titleTimeAtSongStart) < 20
            }) {
                let existing = result[index]
                let total = existing.confirmations + anchor.confirmations
                result[index].titleTimeAtSongStart =
                    (existing.titleTimeAtSongStart * Double(existing.confirmations) + anchor.titleTimeAtSongStart * Double(anchor.confirmations)) / Double(total)
                result[index].confirmations = total
            } else {
                result.append(anchor)
            }
        }
        return result
    }

    private func remoteKey(_ titleKey: String) -> String { "watchalong_soundtrack_\(titleKey)" }

    private func localURL(_ titleKey: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchAlongSoundtrack", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(titleKey).json")
    }

    private func loadLocal(_ titleKey: String) -> [SoundtrackAnchor] {
        guard let data = try? Data(contentsOf: localURL(titleKey)) else { return [] }
        return (try? JSONDecoder().decode([SoundtrackAnchor].self, from: data)) ?? []
    }

    private func saveLocal(_ anchors: [SoundtrackAnchor], _ titleKey: String) {
        guard let data = try? JSONEncoder().encode(anchors) else { return }
        try? data.write(to: localURL(titleKey))
    }
}
#endif
