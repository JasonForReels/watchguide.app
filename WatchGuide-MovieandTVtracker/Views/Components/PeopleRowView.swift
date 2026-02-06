//
//  PeopleRowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct PeopleRowView: View {
    let title: String
    let people: [Person]
    let onPersonTap: (Person) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(people) { person in
                        PersonCard(person: person)
                            .onTapGesture {
                                onPersonTap(person)
                            }
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }
}

struct PersonCard: View {
    let person: Person
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            ProfileImageView(profilePath: person.profilePath, size: 86)
                .shadow(color: .black.opacity(0.15), radius: isHovered ? 8 : 4, y: isHovered ? 4 : 2)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            
            Text(person.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 90)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    PeopleRowView(title: "Trending Actors", people: []) { _ in }
}
