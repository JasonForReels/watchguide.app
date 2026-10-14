import SwiftUI

/// Profile-style header shared by studio, network, franchise and person pages:
/// name with verified badge, handle, stats, Follow and Pops actions.
struct ProfileHeaderView: View {
    struct Stat: Identifiable {
        let value: String
        let label: String
        var id: String { label }
    }

    let entityId: String
    let name: String
    let handle: String
    var verified = true
    let stats: [Stat]
    let accent: Color
    var onPops: (() -> Void)?

    @ObservedObject private var follows = FollowStore.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                if verified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(accent)
                        .accessibilityLabel("Verified")
                }
            }

            Text(handle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(accent)

            HStack(spacing: 28) {
                ForEach(stats) { stat in
                    VStack(spacing: 2) {
                        Text(stat.value)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(stat.label)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    follows.toggle(entityId)
                } label: {
                    let following = follows.isFollowing(entityId)
                    Label(following ? "Following" : "Follow",
                          systemImage: following ? "checkmark" : "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(following ? Color.white.opacity(0.14) : accent,
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                if let onPops {
                    Button(action: onPops) {
                        Label("Pops", systemImage: "flame.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 8)
    }
}
