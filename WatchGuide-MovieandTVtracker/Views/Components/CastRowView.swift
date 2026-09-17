//
//  CastRowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct CastRowView: View {
    let cast: [CastMember]
    let onPersonTap: ((CastMember) -> Void)?
    
    init(cast: [CastMember], onPersonTap: ((CastMember) -> Void)? = nil) {
        self.cast = cast
        self.onPersonTap = onPersonTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(cast.prefix(20)) { member in
                        Button {
                            onPersonTap?(member)
                        } label: {
                            CastMemberCard(member: member)
                        }
                        #if os(tvOS)
                        .buttonStyle(TVOSTransparentButtonStyle())
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct CastMemberCard: View {
    let member: CastMember
    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused
    
    var body: some View {
        let avatarSize = ResponsiveSizing.avatarSize(horizontalSizeClass: horizontalSizeClass, base: 80)
        let textWidth = ResponsiveSizing.avatarSize(horizontalSizeClass: horizontalSizeClass, base: 80)
        let isEngaged = isHovered || isFocused
        VStack(spacing: 8) {
            ProfileImageView(profilePath: member.profilePath, size: avatarSize)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.15), radius: isEngaged ? 8 : 4, y: isEngaged ? 4 : 2)
                .scaleEffect(isEngaged ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEngaged)
            
            VStack(spacing: 2) {
                Text(member.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if let character = member.character, !character.isEmpty {
                    Text(character)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: textWidth)
        }
        #if !os(tvOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
}

// MARK: - Crew Row
struct CrewRowView: View {
    let crew: [CrewMember]
    let onPersonTap: ((CrewMember) -> Void)?
    
    init(crew: [CrewMember], onPersonTap: ((CrewMember) -> Void)? = nil) {
        self.crew = crew
        self.onPersonTap = onPersonTap
    }
    
    var filteredCrew: [CrewMember] {
        let importantJobs = ["Director", "Writer", "Screenplay", "Creator", "Executive Producer", "Producer"]
        return crew.filter { member in
            importantJobs.contains(member.job ?? "")
        }
    }
    
    var body: some View {
        if !filteredCrew.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Crew")
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(filteredCrew.prefix(10), id: \.uniqueId) { member in
                            CrewMemberCard(member: member)
                                .onTapGesture {
                                    onPersonTap?(member)
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct CrewMemberCard: View {
    let member: CrewMember
    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused
    
    var body: some View {
        let avatarSize = ResponsiveSizing.avatarSize(horizontalSizeClass: horizontalSizeClass, base: 70)
        let textWidth = ResponsiveSizing.avatarSize(horizontalSizeClass: horizontalSizeClass, base: 70)
        let isEngaged = isHovered || isFocused
        VStack(spacing: 8) {
            ProfileImageView(profilePath: member.profilePath, size: avatarSize)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.15), radius: isEngaged ? 8 : 4, y: isEngaged ? 4 : 2)
                .scaleEffect(isEngaged ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEngaged)
            
            VStack(spacing: 2) {
                Text(member.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if let job = member.job {
                    Text(job)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: textWidth)
        }
        #if !os(tvOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
}

#Preview {
    CastRowView(cast: [])
}
