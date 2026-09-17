import SwiftUI

struct HubCollection: Identifiable, Hashable {
    let id: Int // TMDB Collection ID or a unique dummy ID for custom lists
    let name: String
    let logoAssetName: String
    let backgroundColor: Color
    let backdropAssetName: String?
    
    // For collections that aren't native TMDB collections (e.g. Character-based)
    struct CustomMediaItem: Hashable, Codable {
        let id: String
        let type: MediaType
    }
    let customItems: [CustomMediaItem]?
    
    init(id: Int, name: String, logoAssetName: String, backgroundColor: Color, backdropAssetName: String? = nil, customItems: [CustomMediaItem]? = nil) {
        self.id = id
        self.name = name
        self.logoAssetName = logoAssetName
        self.backgroundColor = backgroundColor
        self.backdropAssetName = backdropAssetName
        self.customItems = customItems
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
    
    static func == (lhs: HubCollection, rhs: HubCollection) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}
