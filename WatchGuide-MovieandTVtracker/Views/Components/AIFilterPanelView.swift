import SwiftUI

struct AIFilterPanelView: View {
    @State private var title: String
    @State private var company: String
    @State private var yearFrom: String
    @State private var genre: String
    @State private var streaming: String

    private let companyOptions: [String]
    private let yearFromOptions: [String]
    private let genreOptions: [String]
    private let streamingOptions: [String]

    let onCreateList: (AIService.AIFilterPanel) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private static let anyLabel = "Any"

    init(panel: AIService.AIFilterPanel, onCreateList: @escaping (AIService.AIFilterPanel) -> Void) {
        _title     = State(initialValue: panel.title)
        let co = [Self.anyLabel] + panel.companyOptions
        let yo = [Self.anyLabel] + panel.yearFromOptions
        let go = [Self.anyLabel] + panel.genreOptions
        let so = [Self.anyLabel] + panel.streamingOptions
        _company   = State(initialValue: co.contains(panel.company) ? panel.company : Self.anyLabel)
        _yearFrom  = State(initialValue: yo.contains(panel.yearFrom) ? panel.yearFrom : Self.anyLabel)
        _genre     = State(initialValue: go.contains(panel.genre) ? panel.genre : Self.anyLabel)
        _streaming = State(initialValue: so.contains(panel.streaming) ? panel.streaming : Self.anyLabel)
        companyOptions   = co
        yearFromOptions  = yo
        genreOptions     = go
        streamingOptions = so
        self.onCreateList = onCreateList
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.96)
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? Color(white: 0.17) : Color(white: 0.89)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.purple)
                    .font(.subheadline)
                Text("Build Your List")
                    .font(.subheadline)
                    .fontWeight(.bold)
            }

            // Auto-generated title (editable)
            VStack(alignment: .leading, spacing: 5) {
                Label("LIST NAME", systemImage: "pencil")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                TextField("List name…", text: $title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(fieldBackground)
                    )
            }

            Divider()
                .opacity(0.5)

            // Dropdown filters
            VStack(spacing: 8) {
                FilterDropdownRow(
                    icon: "building.2.fill",
                    label: "Production Company",
                    selection: $company,
                    options: companyOptions
                )
                FilterDropdownRow(
                    icon: "calendar",
                    label: "From Year",
                    selection: $yearFrom,
                    options: yearFromOptions
                )
                FilterDropdownRow(
                    icon: "film.fill",
                    label: "Genre",
                    selection: $genre,
                    options: genreOptions
                )
                FilterDropdownRow(
                    icon: "play.tv.fill",
                    label: "Streaming",
                    selection: $streaming,
                    options: streamingOptions
                )
            }

            // Create List button
            Button {
                let resolved = AIService.AIFilterPanel(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    companyOptions: companyOptions.filter { $0 != Self.anyLabel },
                    company:   company   == Self.anyLabel ? "" : company,
                    yearFromOptions: yearFromOptions.filter { $0 != Self.anyLabel },
                    yearFrom:  yearFrom  == Self.anyLabel ? "" : yearFrom,
                    genreOptions: genreOptions.filter { $0 != Self.anyLabel },
                    genre:     genre     == Self.anyLabel ? "" : genre,
                    streamingOptions: streamingOptions.filter { $0 != Self.anyLabel },
                    streaming: streaming == Self.anyLabel ? "" : streaming
                )
                onCreateList(resolved)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Create List")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .cornerRadius(12)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Dropdown Row

private struct FilterDropdownRow: View {
    let icon: String
    let label: String
    @Binding var selection: String
    let options: [String]

    @Environment(\.colorScheme) private var colorScheme

    private var rowBackground: Color {
        colorScheme == .dark ? Color(white: 0.17) : Color(white: 0.89)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.purple.opacity(0.8))
                .frame(width: 18)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.purple)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground)
        )
    }
}
