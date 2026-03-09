import Foundation

#if canImport(AppIntents)
import AppIntents
#endif

#if canImport(CoreTransferable)
import CoreTransferable
#endif

#if canImport(AppIntents)
struct OnscreenMediaEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Movie or TV Show"
    static var defaultQuery = OnscreenMediaEntityQuery()

    let id: String
    let title: String
    let mediaType: String
    let year: String?
    let overview: String
    let genres: String?
    let runtime: String?
    let cast: [String]
    let productionCompanies: [String]

    var displayRepresentation: DisplayRepresentation {
        var subtitleParts: [String] = []
        if !mediaType.isEmpty {
            subtitleParts.append(mediaType)
        }
        if let year, !year.isEmpty {
            subtitleParts.append(year)
        }

        if subtitleParts.isEmpty {
            return DisplayRepresentation(title: "\(title)")
        }

        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitleParts.joined(separator: " • "))"
        )
    }

    var summaryText: String {
        var lines: [String] = []
        lines.append("Title: \(title)")
        lines.append("Type: \(mediaType)")

        if let year, !year.isEmpty {
            lines.append("Year: \(year)")
        }

        if !overview.isEmpty {
            lines.append("Overview: \(overview)")
        }

        if let genres, !genres.isEmpty {
            lines.append("Genres: \(genres)")
        }

        if let runtime, !runtime.isEmpty {
            lines.append("Runtime: \(runtime)")
        }

        if !cast.isEmpty {
            lines.append("Cast: \(cast.joined(separator: ", "))")
        }

        if !productionCompanies.isEmpty {
            lines.append("Production companies: \(productionCompanies.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}

struct OnscreenMediaEntityQuery: EntityQuery {
    func entities(for identifiers: [OnscreenMediaEntity.ID]) async throws -> [OnscreenMediaEntity] {
        await OnscreenMediaEntityRegistry.shared.entities(for: identifiers)
    }

    func suggestedEntities() async throws -> [OnscreenMediaEntity] {
        await OnscreenMediaEntityRegistry.shared.suggestedEntities()
    }
}

actor OnscreenMediaEntityRegistry {
    static let shared = OnscreenMediaEntityRegistry()

    private var entitiesByID: [String: OnscreenMediaEntity] = [:]
    private var lastVisibleEntityID: String?

    func register(_ entity: OnscreenMediaEntity) {
        entitiesByID[entity.id] = entity
        lastVisibleEntityID = entity.id
    }

    func unregister(entityID: String) {
        entitiesByID.removeValue(forKey: entityID)
        if lastVisibleEntityID == entityID {
            lastVisibleEntityID = nil
        }
    }

    func entities(for identifiers: [String]) -> [OnscreenMediaEntity] {
        identifiers.compactMap { entitiesByID[$0] }
    }

    func suggestedEntities() -> [OnscreenMediaEntity] {
        if let lastVisibleEntityID, let entity = entitiesByID[lastVisibleEntityID] {
            return [entity]
        }
        return []
    }
}

#if canImport(CoreTransferable)
extension OnscreenMediaEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \ .summaryText)
    }
}
#endif
#endif
