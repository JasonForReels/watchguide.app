import SwiftUI

struct FranchiseTriviaDetailView: View {
    let franchise: Franchise
    @State private var useChronologicalOrder = false
    @State private var isShowingTheater = false
    @State private var startAtSession: TriviaSession?
    
    var sortedSessions: [TriviaSession] {
        useChronologicalOrder ? franchise.sortedSessionsByChronology : franchise.sortedSessionsByRelease
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Header Image & Description
                headerView
                
                // Controls
                orderToggleSection
                
                // Play All Button
                playAllButton
                
                // Session List
                VStack(alignment: .leading, spacing: 16) {
                    Text("Included Projects")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    ForEach(sortedSessions) { session in
                        SessionRow(session: session) {
                            startAtSession = session
                            isShowingTheater = true
                        }
                    }
                }
                
                Spacer(minLength: 40)
            }
        }
        .applyDefaultBackground()
        .applyInlineNavigationView()
        .fullScreenCover(isPresented: $isShowingTheater) {
            if let startAtSession {
                TriviaTheaterView(
                    franchise: franchise,
                    sessions: sortedSessions,
                    initialIndex: sortedSessions.firstIndex(of: startAtSession)!
                )
            }
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                Color(hex: franchise.accentColor)
                    .frame(height: 200)
                    .overlay {
                        Image(systemName: franchise.iconName)
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.3))
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(franchise.name)
                        .font(.largeTitle)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                }
                .padding(24)
            }
            
            Text(franchise.description)
                .font(.body)
                .padding(.horizontal)
                .foregroundColor(.secondary)
        }
    }
    
    private var orderToggleSection: some View {
        VStack {
            Picker("Order", selection: $useChronologicalOrder) {
                Text("Release Order").tag(false)
                Text("Chronological").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            Text(useChronologicalOrder ? "Watch the events in the order they happened in-universe." : "Watch the movies in the order they were released in theaters.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }
    
    private var playAllButton: some View {
        Button {
            startAtSession = sortedSessions.first!
            isShowingTheater = true
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Play All Trivia Trailers")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(hex: franchise.accentColor))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
        }
    }
}

struct SessionRow: View {
    let session: TriviaSession
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Poster
                ZStack {
                    if let posterPath = session.mediaItem.posterPath {
                        PosterImageView(
                            posterPath: posterPath,
                            backdropPath: nil,
                            size: .small,
                            mediaId: session.mediaItem.id,
                            mediaType: .movie
                        )
                        .frame(width: 60, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 90)
                            .overlay {
                                Image(systemName: "film")
                                    .foregroundColor(.secondary)
                            }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.mediaItem.displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(session.mediaItem.displayDate ?? "TBA")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .applySecondaryBackground()
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}
