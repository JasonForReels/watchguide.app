//
//  PeopleRowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct PeopleRowView: View {
    let title: String
    let people: [Person]
    let onPersonTap: (Person) -> Void
    let onSeeAll: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let displayedPeople = Array(people.prefix(10))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()

                if let onSeeAll {
                    Button(action: onSeeAll) {
                        #if os(tvOS)
                        TVSeeAllButtonLabel()
                        #else
                        Image(systemName: "chevron.right")
                            .font(.headline)
                            .foregroundStyle(colorScheme == .dark ? .white : .gray)
                        #endif
                    }
                    #if os(tvOS)
                    .buttonStyle(TVOSTransparentButtonStyle())
                    #endif
                }
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(displayedPeople) { person in
                        Button {
                            onPersonTap(person)
                        } label: {
                            PersonCard(person: person)
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
            .scrollClipDisabled()
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }
}

struct PersonCard: View {
    let person: Person
    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused
    
    var body: some View {
        let avatarSize = ResponsiveSizing.avatarSize(horizontalSizeClass: horizontalSizeClass, base: 86)
        let nameWidth = ResponsiveSizing.avatarSize(horizontalSizeClass: horizontalSizeClass, base: 90)
        let isEngaged = isHovered || isFocused
        VStack(spacing: 8) {
            ProfileImageView(profilePath: person.profilePath, size: avatarSize)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.15), radius: isEngaged ? 8 : 4, y: isEngaged ? 4 : 2)
                .scaleEffect(isEngaged ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEngaged)
            
            Text(person.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: nameWidth)
        }
        #if !os(tvOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
}

#Preview {
    PeopleRowView(title: "Trending Actors", people: [], onPersonTap: { _ in }, onSeeAll: nil)
}
