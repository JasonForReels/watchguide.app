import SwiftUI

/// Marquee Mode themes: what you own, what's in the store this season, and a
/// one-minute try-on for anything you don't own yet.
struct ThemePacksView: View {
    @StateObject private var store = ThemePackStore.shared
    @Environment(\.colorScheme) private var scheme
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ThemeSwatchHeader(theme: store.activeTheme)
                    .listRowInsets(EdgeInsets())
                if let endsAt = store.previewEndsAt {
                    HStack {
                        Label {
                            Text("Previewing — ends ") + Text(endsAt, style: .relative)
                        } icon: { Image(systemName: "eye") }
                        Spacer()
                        Button("Stop") { store.endPreview() }
                    }
                    .font(.subheadline)
                }
                Toggle("Follow the season", isOn: $store.followsSeason)
            } footer: {
                Text("When you own a theme for the current season or holiday where you live, Marquee Mode switches to it automatically.")
            }

            Section("Your Themes") {
                ForEach(store.ownedThemes) { theme in
                    ThemeRow(theme: theme, isActive: store.activeTheme.id == theme.id) {
                        store.select(theme)
                    }
                }
            }

            ForEach(store.storefrontPacks) { pack in
                Section {
                    PackHeader(pack: pack, price: store.displayPrice(for: pack),
                               isPurchasing: store.isPurchasing) {
                        Task { message = await store.purchase(pack).message }
                    }
                    ForEach(ThemeCatalog.themes(in: pack)) { theme in
                        ThemeRow(theme: theme, isActive: store.previewTheme?.id == theme.id,
                                 trailing: store.owns(themeID: theme.id) ? nil : "Try") {
                            store.startPreview(theme)
                        }
                    }
                }
            }

            Section {
                Button("Restore Purchases") { Task { await store.restore() } }
            } footer: {
                Text("Theme packs are one-time purchases, yours to keep and restore forever — even after a seasonal pack leaves the store. Family Sharing is supported.")
            }
        }
        .navigationTitle("Themes")
        .environment(\.wgTheme, store.activeTheme)
        .tint(ResolvedTheme(theme: store.activeTheme, scheme: scheme).accent)
        .alert("Themes", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
}

// MARK: - Pieces

private struct ThemeSwatchHeader: View {
    let theme: WGTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ResolvedTheme(theme: theme, scheme: scheme)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 0)
                        .fill(LinearGradient(colors: [t.surface, i.isMultiple(of: 2) ? t.accent : t.secondary],
                                             startPoint: .top, endPoint: .bottom))
                        .aspectRatio(2/3, contentMode: .fit)
                        .environment(\.wgTheme, theme)
                        .themedPosterFrame()
                }
            }
            Text(theme.name).font(.title2.bold()).foregroundStyle(t.text)
            Text(theme.mood).font(.subheadline).foregroundStyle(t.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.background)
        .animation(.easeInOut, value: theme)
        .accessibilityElement(children: .combine)
    }
}

private struct ThemeRow: View {
    let theme: WGTheme
    let isActive: Bool
    var trailing: String? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ResolvedTheme(theme: theme, scheme: scheme)
        Button(action: action) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach([t.background, t.accent, t.secondary], id: \.self) { $0 }
                }
                .frame(width: 44, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                VStack(alignment: .leading) {
                    Text(theme.name).foregroundStyle(.primary)
                    Text(theme.mood).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                } else if let trailing {
                    Text(trailing).font(.subheadline).foregroundStyle(.tint)
                }
            }
        }
    }
}

private struct PackHeader: View {
    let pack: ThemePack
    let price: String
    let isPurchasing: Bool
    let buy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pack.symbol).font(.title2).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name).font(.headline)
                Text(pack.tagline).font(.caption).foregroundStyle(.secondary)
                if case .season = pack.availability {
                    Text("Available this season only").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(price, action: buy)
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing)
        }
        .padding(.vertical, 4)
    }
}
