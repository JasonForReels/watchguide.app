import Foundation

/// Local store of the studios, networks, franchises and people the user follows.
/// Entity ids are stable slugs such as "studio-marvel".
@MainActor
final class FollowStore: ObservableObject {
    static let shared = FollowStore()

    @Published private(set) var followedIds: Set<String>

    private let defaultsKey = "followedEntityIds"

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        followedIds = Set(saved)
    }

    func isFollowing(_ id: String) -> Bool {
        followedIds.contains(id)
    }

    func toggle(_ id: String) {
        if followedIds.contains(id) {
            followedIds.remove(id)
        } else {
            followedIds.insert(id)
        }
        UserDefaults.standard.set(Array(followedIds), forKey: defaultsKey)
    }
}
