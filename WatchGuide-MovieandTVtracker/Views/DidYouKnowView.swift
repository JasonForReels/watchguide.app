import SwiftUI

struct DidYouKnowView: View {
    @State private var franchises: [Franchise] = [
        MCUFactsProvider.getMCUFranchise()
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                
                VStack(spacing: 20) {
                    ForEach(franchises) { franchise in
                        NavigationLink(destination: FranchiseTriviaDetailView(franchise: franchise)) {
                            FranchiseCard(franchise: franchise)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                
            }
        }
        .applyDefaultBackground()
        .navigationTitle("Did You Know?")
        .applyInlineNavigationView()
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discover the Franchise")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            
            Text("Watch trailers and uncover legendary facts from your favorite cinematic universes.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 20)
    }
}

struct FranchiseCard: View {
    let franchise: Franchise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                // Background Gradient or Hero Image
                LinearGradient(
                    colors: [Color(hex: franchise.accentColor), Color(hex: franchise.accentColor).opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 180)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: franchise.iconName)
                            .font(.title2)
                        Text(franchise.name.uppercased())
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.black)
                            .tracking(1.2)
                    }
                    .foregroundColor(.white)
                    
                    Text("\(franchise.sessions.count) Projects")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2))
                        .clipShape(Capsule())
                        .foregroundColor(.white)
                }
                .padding(20)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(franchise.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(20)
            .padding(20)
            .applySecondaryBackground()
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
}

