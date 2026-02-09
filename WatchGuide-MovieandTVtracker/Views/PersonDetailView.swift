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
    @StateObject private var viewModel: PersonDetailViewModel
    @State private var selectedItem: MediaItem?
    @State private var selectedTab = 0
    
    init(personId: Int, personName: String, profilePath: String?) {
        self.personId = personId
        self.personName = personName
        self.profilePath = profilePath
        _viewModel = StateObject(wrappedValue: PersonDetailViewModel(personId: personId))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Biography
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
                    
                    // Filmography tabs
                    VStack(spacing: 16) {
                        Picker("Credits", selection: $selectedTab) {
                            Text("Movies (\(viewModel.movieCredits.count))").tag(0)
                            Text("TV Shows (\(viewModel.tvCredits.count))").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        // Credits grid
                        let credits = selectedTab == 0 ? viewModel.movieCredits : viewModel.tvCredits
                        
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
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                            ], spacing: 20) {
                                ForEach(credits) { item in
                                    MediaPosterCard(item: item)
                                        .onTapGesture {
                                            selectedItem = item
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(personName)
            .navigationBarTitleDisplayMode(.inline)
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
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.5))
                }
            }
        }
        .task {
            await viewModel.loadDetails()
        }
        .sheet(item: $selectedItem) { item in
            MediaDetailView(item: item)
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
                        if let date = self.dateFormatter.date(from: bday) {
                            self.birthday = self.displayFormatter.string(from: date)
                        } else {
                            self.birthday = bday
                        }
                    }
                    
                    if let dday = person.deathday {
                        if let date = self.dateFormatter.date(from: dday) {
                            self.deathday = self.displayFormatter.string(from: date)
                        } else {
                            self.deathday = dday
                        }
                    }
                } catch {
                    print("Error loading person details: \(error)")
                }
            }
            
            // Movie credits
            group.addTask { @MainActor in
                do {
                    let credits = try await TMDBService.shared.getPersonMovieCredits(id: pid)
                    var allMovies: [MediaItem] = []
                    if let cast = credits.cast { allMovies.append(contentsOf: cast) }
                    if let crew = credits.crew { allMovies.append(contentsOf: crew) }
                    
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
                    var allShows: [MediaItem] = []
                    if let cast = credits.cast { allShows.append(contentsOf: cast) }
                    if let crew = credits.crew { allShows.append(contentsOf: crew) }
                    
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
