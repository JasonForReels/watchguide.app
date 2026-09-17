//
//  StubBoxView.swift
//  WatchGuide-MovieandTVtracker
//
//  Your watch history as a stack of ticket stubs, grouped by month.
//

import SwiftUI

struct StubBoxView: View {
    @ObservedObject private var store = TicketStubStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: .sectionHeaders) {
                if store.stubs.isEmpty {
                    ContentUnavailableView(
                        "No Ticket Stubs",
                        systemImage: "ticket",
                        description: Text("When you finish something on Tonight, swipe it up to keep a stub.")
                    )
                    .padding(.top, 80)
                } else {
                    summary
                }

                ForEach(store.byMonth, id: \.month) { group in
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                            ForEach(group.stubs) { stub in
                                StubCard(stub: stub)
                                    .contextMenu {
                                        Button("Delete Stub", systemImage: "trash", role: .destructive) {
                                            withAnimation { store.remove(stub) }
                                        }
                                    }
                            }
                        }
                    } header: {
                        Text(group.month)
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .background(.bar)
                    }
                }
            }
            .padding(.horizontal)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Ticket Stubs")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            stat("\(store.stubs.count)", "Watched")
            stat("\(store.stubs.filter { $0.verdict == .loved }.count)", "Loved")
            stat("\(Set(store.stubs.map(\.company).filter { !$0.isEmpty }).count)", "Watch Buddies")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title.bold()).contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct StubCard: View {
    let stub: TicketStub
    /// Fraction down the card where the perforation sits, so the notches line up with it.
    @State private var tearY: CGFloat = 0
    @State private var height: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImageView(url: TMDBService.shared.imageURL(path: stub.posterPath, size: .small), cornerRadius: 8)
                    .frame(width: 60, height: 90)
                VStack(alignment: .leading, spacing: 4) {
                    Text(stub.mediaType == .tv ? "SERIES" : "MOVIE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(stub.title)
                        .font(.headline)
                        .lineLimit(2)
                    if let year = stub.year {
                        Text(year).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)

            Perforation()
                .padding(.horizontal, 14)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("stub")).midY } action: { tearY = $0 }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    field("Watched", stub.watchedAt.formatted(date: .abbreviated, time: .omitted))
                    field("Seat", stub.seat.replacingOccurrences(of: "ROW ", with: "").replacingOccurrences(of: " · SEAT ", with: "·"))
                }
                GridRow {
                    field("Verdict", stub.verdict.label)
                    field("With", stub.company.isEmpty ? "Solo" : stub.company)
                }
            }
            .padding(16)

            if !stub.note.isEmpty {
                Text(stub.note)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom], 16)
            }
        }
        .coordinateSpace(.named("stub"))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .background(.background.secondary, in: TicketShape(notchPosition: height > 0 ? tearY / height : 0.5))
        .overlay(alignment: .topTrailing) {
            Image(systemName: stub.verdict.symbol)
                .font(.title3)
                .foregroundStyle(Reel.accent)
                .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium)).lineLimit(1)
        }
    }
}
