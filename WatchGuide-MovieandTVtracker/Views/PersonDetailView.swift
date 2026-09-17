//
//  PersonDetailView.swift
//  WatchGuide-MovieandTVtracker
//
//  Displays a person's filmography and details
//

import SwiftUI

struct PersonDetailView: View {
    let personId: Int
    let personName: String
    let profilePath: String?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel: PersonDetailViewModel
    @State private var selectedItem: MediaItem?
    @State private var selectedTab = 0
    @State private var currentBackdropPath: String?
    
    init(personId: Int, personName: String, profilePath: String?) {
        self.personId = personId
        self.personName = personName
        self.profilePath = profilePath
        _viewModel = StateObject(wrappedValue: PersonDetailViewModel(personId: personId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Cinematic Backdrop (Dynamic)
                PersonCinematicBackdrop(path: currentBackdropPath)

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        biographySection
                        creditsSection
                        
                        RemoteBannerView(placement: .personDetail)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .colorScheme(.dark)
            .navigationTitle(personName)
            .inlineNavTitleIfSupported()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .overlay { loadingOverlay }
        }
        .task {
            await viewModel.loadDetails()
        }
        .mediaDetailPresentation(item: $selectedItem)
    }
    
    @ViewBuilder
    private var biographySection: some View {
        if let bio = viewModel.biography, !bio.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Biography")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text(bio)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(viewModel.showFullBio ? nil : 5)
                
                if bio.count > 200 {
                    Button {
                        withAnimation {
                            viewModel.showFullBio.toggle()
                        }
                    } label: {
                        Text(viewModel.showFullBio ? "Show Less" : "Read More")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var creditsSection: some View {
        let isRegular = horizontalSizeClass == .regular
        let filmographyPosterWidth = ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass)
        let credits = selectedTab == 0 ? viewModel.movieCredits : viewModel.tvCredits

        VStack(spacing: 16) {
            Picker("Credits", selection: $selectedTab) {
                Text("Movies (\(viewModel.movieCredits.count))").tag(0)
                Text("TV Shows (\(viewModel.tvCredits.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            if credits.isEmpty && !viewModel.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No \(selectedTab == 0 ? "movies" : "TV shows") found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: filmographyPosterWidth, maximum: filmographyPosterWidth), spacing: isRegular ? 28 : 20)
                ], spacing: isRegular ? 28 : 20) {
                    ForEach(credits) { item in
                        CreditGridItem(item: item, currentBackdropPath: $currentBackdropPath, selectedItem: $selectedItem)
                    }
                }
                .padding(.horizontal, isRegular ? 28 : 16)
            }
        }
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if viewModel.isLoading {
            ProgressView()
                .scaleEffect(1.2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.4))
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Profile image
            ProfileImageView(profilePath: profilePath, size: 120)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
            
            // Name
            Text(personName)
                .font(.title2)
                .fontWeight(.bold)
            
            // Known for
            if let knownFor = viewModel.knownForDepartment {
                Text(knownFor)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Personal info
            HStack(spacing: 24) {
                if let birthday = viewModel.birthday {
                    VStack(spacing: 4) {
                        Text("Born")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(birthday)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                
                if let deathday = viewModel.deathday {
                    VStack(spacing: 4) {
                        Text("Died")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(deathday)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                
                if let birthplace = viewModel.placeOfBirth {
                    VStack(spacing: 4) {
                        Text("Birthplace")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(birthplace)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

struct CreditGridItem: View {
    let item: MediaItem
    @Binding var currentBackdropPath: String?
    @Binding var selectedItem: MediaItem?
    
    var body: some View {
        Button {
            selectedItem = item
        } label: {
            MediaPosterCard(item: item)
                #if os(tvOS)
                .onAppear {
                    if currentBackdropPath == nil {
                        currentBackdropPath = item.backdropPath
                    }
                }
                #endif
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .onFocusChange { isFocused in
            if isFocused {
                withAnimation(.easeInOut(duration: 0.5)) {
                    currentBackdropPath = item.backdropPath
                }
            }
        }
        #endif
    }
}

// MARK: - Person Detail View Model
@MainActor
class PersonDetailViewModel: ObservableObject {
    let personId: Int
    
    @Published var biography: String?
    @Published var birthday: String?
    @Published var deathday: String?
    @Published var placeOfBirth: String?
    @Published var knownForDepartment: String?
    @Published var movieCredits: [MediaItem] = []
    @Published var tvCredits: [MediaItem] = []
    @Published var isLoading = true
    @Published var showFullBio = false
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    
    init(personId: Int) {
        self.personId = personId
    }
    
    func loadDetails() async {
        isLoading = true
        let pid = personId
        
        // Load all three concurrently
        await withTaskGroup(of: Void.self) { group in
            // Person details
            group.addTask { @MainActor in
                do {
                    let person = try await TMDBService.shared.getPersonDetails(id: pid)
                    self.biography = person.biography
                    self.knownForDepartment = person.knownForDepartment
                    self.placeOfBirth = person.placeOfBirth
                    
                    if let bday = person.birthday {
                        self.birthday = self.dateFormatter.date(from: bday).map { self.displayFormatter.string(from: $0) } ?? bday
                    }
                    
                    if let dday = person.deathday {
                        self.deathday = self.dateFormatter.date(from: dday).map { self.displayFormatter.string(from: $0) } ?? dday
                    }
                } catch {
                    print("Error loading person details: \(error)")
                }
            }
            
            // Movie credits
            group.addTask { @MainActor in
                do {
                    let credits = try await TMDBService.shared.getPersonMovieCredits(id: pid)
                    var allMovies: [MediaItem] = (credits.cast ?? []) + (credits.crew ?? [])
                    
                    var seen = Set<Int>()
                    self.movieCredits = allMovies
                        .filter { item in
                            if seen.contains(item.id) { return false }
                            seen.insert(item.id)
                            return true
                        }
                        .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                } catch {
                    print("Error loading movie credits: \(error)")
                }
            }
            
            // TV credits
            group.addTask { @MainActor in
                do {
                    let credits = try await TMDBService.shared.getPersonTVCredits(id: pid)
                    var allShows: [MediaItem] = (credits.cast ?? []) + (credits.crew ?? [])
                    
                    var seen = Set<Int>()
                    self.tvCredits = allShows
                        .filter { item in
                            if seen.contains(item.id) { return false }
                            seen.insert(item.id)
                            return true
                        }
                        .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                } catch {
                    print("Error loading TV credits: \(error)")
                }
            }
        }
        
        isLoading = false
    }
}

#Preview {
    PersonDetailView(personId: 287, personName: "Brad Pitt", profilePath: nil)
}

struct PersonCinematicBackdrop: View {
    let path: String?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let path = path {
                ResilientAsyncImage(url: TMDBService.shared.imageURL(path: path, size: .backdrop)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity.combined(with: .scale(scale: 1.1)))
                    } else {
                        Color.black
                    }
                }
                .overlay {
                    #if os(tvOS)
                    Color.black.opacity(0.4)
                    #else
                    Color.black.opacity(0.6)
                    #endif
                }
                .blur(radius: 20)
                .ignoresSafeArea()
            }
            
            // Bottom gradient for legibility
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}
