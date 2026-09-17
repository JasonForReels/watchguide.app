import SwiftUI

struct TriviaTheaterView: View {
    @Environment(\.dismiss) private var dismiss
    let franchise: Franchise
    let sessions: [TriviaSession]
    @State private var currentIndex: Int
    @State private var currentTime: TimeInterval = 0
    @State private var activeFact: TriviaFact?
    @State private var isMuted: Bool = false
    @State private var playerVolume: Double = 1.0
    @State private var isPaused: Bool = false
    
    init(franchise: Franchise, sessions: [TriviaSession], initialIndex: Int) {
        self.franchise = franchise
        self.sessions = sessions
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var currentSession: TriviaSession {
        sessions[currentIndex]
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // The Player
            EmbeddedTrailerPlayer(
                videoKey: currentSession.videoKey,
                title: currentSession.mediaItem.displayTitle,
                autoPlay: true,
                showsControls: true, // We allow standard controls but overlay our own
                onPlaybackEnded: {
                    advanceToNext()
                },
                onProgress: { time in
                    handleProgress(time)
                }
            )
            .volume(playerVolume)
            .id(currentSession.id) // Force reload on session change
            
            // Fact Overlay
            VStack {
                Spacer()
                if let activeFact {
                    TriviaFactPopup(fact: activeFact)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 80)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: activeFact)
            
            // Top Controls
            VStack {
                HStack(alignment: .top) {
                    dismissButton
                    
                    Spacer()
                    
                    sessionInfo
                }
                .padding()
                
                Spacer()
            }
        }
    }
    
    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.8))
                .background(Circle().fill(.black.opacity(0.3)))
        }
    }
    
    private var sessionInfo: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(currentSession.mediaItem.displayTitle)
                .font(.headline)
                .foregroundColor(.white)
            
            Text("\(currentIndex + 1) of \(sessions.count)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Material.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Logic
    
    private func handleProgress(_ time: TimeInterval) {
        currentTime = time
        
        // Find if any fact should be active
        let fact = currentSession.facts.first { fact in
            time >= fact.startTime && time <= (fact.startTime + fact.duration)
        }
        
        if fact != activeFact {
            activeFact = fact
            // Duck volume if fact is active
            withAnimation(.easeInOut(duration: 0.5)) {
                playerVolume = (fact != nil) ? 0.2 : 1.0
            }
        }
    }
    
    private func advanceToNext() {
        if currentIndex < sessions.count - 1 {
            withAnimation {
                currentIndex += 1
                activeFact = nil
                playerVolume = 1.0
            }
        } else {
            dismiss()
        }
    }
}

struct TriviaFactPopup: View {
    let fact: TriviaFact
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: fact.isMetaFact ? "building.2.fill" : "sparkles")
                    .foregroundColor(.yellow)
                    .font(.headline)
                
                Text(fact.isMetaFact ? "DID YOU KNOW? (FRANCHISE FACT)" : "DID YOU KNOW?")
                    .font(.caption.weight(.black))
                    .tracking(1.5)
                    .foregroundColor(.yellow)
            }
            
            Text(fact.text)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Color.black.opacity(0.4)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }
}

// Extension to pass volume to the underlying player
extension EmbeddedTrailerPlayer {
    func volume(_ value: Double) -> some View {
        var copy = self
        copy.volume = value
        return copy
    }
}
