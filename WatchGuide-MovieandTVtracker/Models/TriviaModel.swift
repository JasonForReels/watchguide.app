import Foundation

// MARK: - Trivia Fact
struct TriviaFact: Codable, Identifiable, Hashable {
    var id: String { text }
    let text: String
    let startTime: TimeInterval
    let duration: TimeInterval
    let relatedMediaId: Int? // Optional: link to another movie (for franchise connections)
    let isMetaFact: Bool     // True for company/franchise-wide facts
    
    init(text: String, startTime: TimeInterval, duration: TimeInterval = 6, relatedMediaId: Int? = nil, isMetaFact: Bool = false) {
        self.text = text
        self.startTime = startTime
        self.duration = duration
        self.relatedMediaId = relatedMediaId
        self.isMetaFact = isMetaFact
    }
}

// MARK: - Trivia Session
struct TriviaSession: Codable, Identifiable, Hashable {
    let id: String
    let mediaItem: MediaItem
    let videoKey: String
    let facts: [TriviaFact]
    let releaseDate: Date
    let chronologicalDate: Date // Date used for timeline sorting
    
    init(mediaItem: MediaItem, videoKey: String, facts: [TriviaFact], releaseDate: Date, chronologicalDate: Date? = nil) {
        self.id = "\(mediaItem.id)_\(videoKey)"
        self.mediaItem = mediaItem
        self.videoKey = videoKey
        self.facts = facts
        self.releaseDate = releaseDate
        self.chronologicalDate = chronologicalDate ?? releaseDate
    }
}

// MARK: - Franchise
struct Franchise: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let accentColor: String // Hex color for the UI
    let iconName: String
    let sessions: [TriviaSession]
    
    var sortedSessionsByRelease: [TriviaSession] {
        sessions.sorted { $0.releaseDate < $1.releaseDate }
    }
    
    var sortedSessionsByChronology: [TriviaSession] {
        sessions.sorted { $0.chronologicalDate < $1.chronologicalDate }
    }
}

// MARK: - Trivia Playlist
struct TriviaPlaylist {
    let franchise: Franchise
    var sessions: [TriviaSession]
    var currentIndex: Int = 0
    
    var currentSession: TriviaSession? {
        guard sessions.indices.contains(currentIndex) else { return nil }
        return sessions[currentIndex]
    }
    
    mutating func next() -> Bool {
        if currentIndex < sessions.count - 1 {
            currentIndex += 1
            return true
        }
        return false
    }
    
    mutating func previous() -> Bool {
        if currentIndex > 0 {
            currentIndex -= 1
            return true
        }
        return false
    }
}
