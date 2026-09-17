//
//  AtlasBriefingCard.swift
//  WatchGuide-MovieandTVtracker
//
//  Two small pieces of the Atlas conversation UI:
//
//  • AtlasBriefingCard — what Atlas leads with before you've said anything.
//    Built from local data by AtlasProactiveEngine, so it's there instantly.
//  • AtlasActionReceiptsView — what Atlas actually did, rendered from executed
//    actions rather than from anything the model claimed in its reply.
//

import SwiftUI

// MARK: - Proactive briefing

struct AtlasBriefingCard: View {
    /// Called with a ready-made prompt when the user taps an item.
    let onAsk: (String) -> Void

    @AppStorage(AtlasPersona.storageKey) private var personaRaw = AtlasPersona.default.rawValue
    @ObservedObject private var proactive = AtlasProactiveEngine.shared

    private var persona: AtlasPersona {
        AtlasPersona(rawValue: personaRaw) ?? .default
    }

    var body: some View {
        if let briefing = proactive.briefing, !briefing.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: persona.sfSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(persona.accentColor)
                    Text(briefing.opener)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(briefing.items) { item in
                        Button {
                            onAsk(prompt(for: item))
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: item.sfSymbol)
                                    .font(.system(size: 13))
                                    .foregroundStyle(persona.accentColor)
                                    .frame(width: 18)
                                Text(item.text)
                                    .font(.footnote)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(persona.accentColor.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(persona.accentColor.opacity(0.25), lineWidth: 1)
            )
            .onAppear { proactive.markBriefingSeen() }
        }
    }

    /// Turns a briefing line into something worth sending to Atlas.
    private func prompt(for item: AtlasProactiveEngine.BriefingItem) -> String {
        guard let title = item.relatedTitle else { return item.text }
        switch item.kind {
        case .nextEpisode:  return "Where can I watch the next episode of \(title)?"
        case .releasingNow: return "Tell me about \(title) — is it worth watching?"
        case .releasingSoon: return "What should I know about \(title) before it comes out?"
        case .stalled:      return "Remind me what happened so far in \(title)."
        case .nudge:        return "Should I finally watch \(title), or drop it from my watchlist?"
        }
    }
}

// MARK: - Action receipts

struct AtlasActionReceiptsView: View {
    let receipts: [AtlasActionReceipt]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(receipts) { receipt in
                HStack(spacing: 8) {
                    Image(systemName: receipt.sfSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(receipt.succeeded ? Color.green : Color.orange)
                    Text(receipt.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Actions taken")
    }
}
