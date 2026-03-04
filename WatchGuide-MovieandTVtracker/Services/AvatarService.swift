//
//  AvatarService.swift
//  WatchGuide-MovieandTVtracker
//
//  Fetches and caches avatar images from the remote avatars.json
//

import Foundation

// MARK: - Avatar Models

struct AvatarCategory: Codable, Identifiable {
    let name: String
    let avatars: [AvatarItem]
    
    var id: String { name }
}

struct AvatarItem: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let url: String
    
    static func == (lhs: AvatarItem, rhs: AvatarItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Avatar Service

@MainActor
class AvatarService: ObservableObject {
    static let shared = AvatarService()
    
    @Published private(set) var categories: [AvatarCategory] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    private let avatarsURL = "https://raw.githubusercontent.com/WatchGuide-app/Watch-Guide-Avatars/refs/heads/main/avatars.json"
    private let avatarsBaseURL = "https://raw.githubusercontent.com/WatchGuide-app/Watch-Guide-Avatars/refs/heads/main/"
    private var hasFetched = false
    
    /// All avatars flattened across categories
    var allAvatars: [AvatarItem] {
        categories.flatMap { $0.avatars }
    }
    
    /// Find an avatar by its URL
    func avatar(forURL url: String) -> AvatarItem? {
        allAvatars.first { $0.url == url }
    }
    
    /// Find an avatar by its ID
    func avatar(forId id: String) -> AvatarItem? {
        allAvatars.first { $0.id == id }
    }

    /// Normalize remote avatar paths so views can always load valid image URLs.
    private func normalizedAvatarURL(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }

        let normalizedPath = trimmed.replacingOccurrences(of: #"^\./"#, with: "", options: .regularExpression)
        return avatarsBaseURL + normalizedPath
    }
    
    /// Fetch avatars from the remote JSON (only fetches once per session unless forced)
    func fetchAvatars(force: Bool = false) async {
        guard !hasFetched || force else { return }
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            guard let url = URL(string: avatarsURL) else {
                error = "Invalid avatar URL"
                isLoading = false
                return
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                error = "Failed to fetch avatars"
                isLoading = false
                return
            }
            
            let decoder = JSONDecoder()
            
            // Try decoding as an object with "categories" key
            if let wrapper = try? decoder.decode(AvatarCategoriesWrapper.self, from: data) {
                categories = wrapper.categories
            }
            // Try decoding as a direct array of categories
            else if let directCategories = try? decoder.decode([AvatarCategory].self, from: data) {
                categories = directCategories
            }
            // Try decoding as a flat array of avatar items
            else if let flatAvatars = try? decoder.decode([AvatarItem].self, from: data) {
                categories = [AvatarCategory(name: "Avatars", avatars: flatAvatars)]
            }
            // Try decoding as a dictionary of category name -> [AvatarItem]
            else if let dict = try? decoder.decode([String: [AvatarItem]].self, from: data) {
                categories = dict.map { AvatarCategory(name: $0.key, avatars: $0.value) }
                    .sorted { $0.name < $1.name }
            }
            // Legacy/current repo format: [{id, name, category, image}]
            else if let legacyItems = try? decoder.decode([LegacyAvatarItem].self, from: data) {
                let grouped = Dictionary(grouping: legacyItems) { item in
                    item.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Avatars" : item.category
                }
                categories = grouped
                    .map { categoryName, items in
                        AvatarCategory(
                            name: categoryName,
                            avatars: items.map { item in
                                AvatarItem(
                                    id: item.id,
                                    name: item.name,
                                    url: normalizedAvatarURL(item.image)
                                )
                            }
                        )
                    }
                    .sorted { $0.name < $1.name }
            }
            else {
                error = "Unrecognized avatar format"
            }
            
            hasFetched = true
        } catch {
            self.error = "Failed to load avatars: \(error.localizedDescription)"
            print("AvatarService error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Wrapper for {"categories": [...]} format
private struct AvatarCategoriesWrapper: Codable {
    let categories: [AvatarCategory]
}

private struct LegacyAvatarItem: Codable {
    let id: String
    let name: String
    let category: String
    let image: String
}
