#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

public struct TripActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var estimatedTravelSeconds: TimeInterval
        public var leaveByDate: Date
        public var isLeavingSoon: Bool // Used to highlight when it's very close
        
        public init(estimatedTravelSeconds: TimeInterval, leaveByDate: Date, isLeavingSoon: Bool) {
            self.estimatedTravelSeconds = estimatedTravelSeconds
            self.leaveByDate = leaveByDate
            self.isLeavingSoon = isLeavingSoon
        }
    }

    public var movieTitle: String
    public var cinemaName: String
    public var showtimeDate: Date
    
    public init(movieTitle: String, cinemaName: String, showtimeDate: Date) {
        self.movieTitle = movieTitle
        self.cinemaName = cinemaName
        self.showtimeDate = showtimeDate
    }
}
#endif
