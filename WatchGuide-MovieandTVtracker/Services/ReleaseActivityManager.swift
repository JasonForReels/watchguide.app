#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Combine
import Foundation

@MainActor
class ReleaseActivityManager: ObservableObject {
    static let shared = ReleaseActivityManager()
    
    private var cancellables = Set<AnyCancellable>()
    private var activeReleaseActivities: [String: Activity<ReleaseActivityAttributes>] = [:]
    
    private init() {
        StorageService.shared.$wantToWatch
            .sink { [weak self] items in
                Task { [weak self] in
                    await self?.checkReleases(items: items)
                }
            }
            .store(in: &cancellables)
    }
    
    func checkReleases(items: [SavedMediaItem]) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for item in items {
            guard let releaseDateStr = item.releaseDate,
                  let releaseDate = TMDBService.shared.date(from: releaseDateStr) else {
                continue
            }
            
            let releaseDay = calendar.startOfDay(for: releaseDate)
            
            if releaseDay == today {
                await startActivityIfNeeded(for: item, releaseDate: releaseDate)
            } else {
                await stopActivity(for: item.id)
            }
        }
    }
    
    private func startActivityIfNeeded(for item: SavedMediaItem, releaseDate: Date) async {
        guard activeReleaseActivities[item.id] == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = ReleaseActivityAttributes(
            mediaTitle: item.title,
            releaseDate: releaseDate,
            mediaType: item.mediaType.rawValue
        )
        
        let initialContentState = ReleaseActivityAttributes.ContentState(
            releaseStatus: "Out Today!",
            progress: 1.0
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialContentState, staleDate: nil)
            )
            activeReleaseActivities[item.id] = activity
            print("Started Release Live Activity for \(item.title)")
        } catch {
            print("Error starting release activity: \(error.localizedDescription)")
        }
    }
    
    private func stopActivity(for itemId: String) async {
        guard let activity = activeReleaseActivities[itemId] else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        activeReleaseActivities.removeValue(forKey: itemId)
    }
}
#endif
