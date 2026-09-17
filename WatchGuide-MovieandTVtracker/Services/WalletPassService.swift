#if canImport(PassKit) && os(iOS)
import PassKit
import UIKit

@MainActor
final class WalletPassService: ObservableObject {
    static let shared = WalletPassService()
    
    @Published var isGeneratingPass = false
    @Published var passError: String?
    
    private let passGenerationEndpoint = URL(string: "https://example.com/generate-trip-pass")!
    
    func generateAndAddPass(for trip: CinemaTrip) async {
        isGeneratingPass = true
        passError = nil
        
        defer { isGeneratingPass = false }
        
        do {
            var request = URLRequest(url: passGenerationEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "movieTitle": trip.movieTitle,
                "cinemaName": trip.cinemaName,
                "showtimeDate": trip.showtimeDate.timeIntervalSince1970
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as! HTTPURLResponse
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
                throw NSError(domain: "SupabaseEdge", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned \(httpResponse.statusCode): \(errorMessage)"])
            }
            
            guard let pass = try? PKPass(data: data) else {
                throw NSError(domain: "PassKit", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid pass data received. Ensure your Supabase Edge Function returns a valid signed .pkpass buffer."])
            }
            
            if let vc = PKAddPassesViewController(pass: pass) {
                presentInRoot(vc)
            }
            
        } catch {
            passError = error.localizedDescription
        }
    }
    
    private func presentInRoot(_ viewController: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        var top = rootVC
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(viewController, animated: true)
    }
}
#endif
