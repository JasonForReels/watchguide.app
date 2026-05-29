//
//  VPNDetectionService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor VPNDetectionService {
    static let shared = VPNDetectionService()

    // MARK: - Configuration
    private let apiKey = "46b8cef953de450f8b7141da67141cc0"
    private let baseURL = "https://vpnapi.io/api"
    private let cacheTTL: TimeInterval = 1800 // 30 minutes

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Cached State
    private var cachedResult: VPNCheckResult?
    private var lastCheckTime: Date?
    private var checkInProgress: Task<VPNCheckResult, Never>?

    private init() {}

    // MARK: - Public API

    /// Returns true if a VPN, proxy, or Tor connection is detected.
    /// Checks once per session / every 30 minutes. Returns false on API errors (fail-open).
    var isVPNDetected: Bool {
        get async {
            let result = await checkVPN()
            return result.isVPN || result.isProxy || result.isTor
        }
    }

    // MARK: - Private

    private func checkVPN() async -> VPNCheckResult {
        // Return cached result if still valid
        if let cached = cachedResult, let lastCheck = lastCheckTime,
           Date().timeIntervalSince(lastCheck) < cacheTTL {
            return cached
        }

        // Deduplicate concurrent requests
        if let existing = checkInProgress {
            return await existing.value
        }

        let task = Task<VPNCheckResult, Never> {
            guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
                return .notDetected
            }

            do {
                let (data, response) = try await session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    return .notDetected
                }

                let decoded = try JSONDecoder().decode(VPNAPIResponse.self, from: data)
                let result = VPNCheckResult(
                    isVPN: decoded.security.vpn,
                    isProxy: decoded.security.proxy,
                    isTor: decoded.security.tor
                )
                return result
            } catch {
                print("VPNDetectionService: Check failed - \(error)")
                return .notDetected
            }
        }

        checkInProgress = task
        let result = await task.value
        cachedResult = result
        lastCheckTime = Date()
        checkInProgress = nil
        return result
    }

    // MARK: - Models

    private struct VPNCheckResult {
        let isVPN: Bool
        let isProxy: Bool
        let isTor: Bool

        static let notDetected = VPNCheckResult(isVPN: false, isProxy: false, isTor: false)
    }

    private struct VPNAPIResponse: Decodable {
        let security: SecurityInfo
    }

    private struct SecurityInfo: Decodable {
        let vpn: Bool
        let proxy: Bool
        let tor: Bool
    }
}
