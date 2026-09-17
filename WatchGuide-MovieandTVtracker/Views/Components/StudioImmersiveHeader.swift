import SwiftUI

struct StudioImmersiveHeader: View {
    let studioName: String
    let logoName: String
    let accentColor: Color
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isShowingContent = false
    
    var body: some View {
        ZStack {
            // Background - in a real app, this would be a studio-specific hero image or loop
            #if os(tvOS)
            Rectangle()
                .fill(LinearGradient(
                    colors: [accentColor.opacity(0.8), .black],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .ignoresSafeArea()
            #else
            Rectangle()
                .fill(accentColor.opacity(0.1))
                .ignoresSafeArea()
            #endif
            
            VStack(spacing: 24) {
                // The Studio Logo
                Image(logoName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .frame(height: ResponsiveSizing.studioHubHeaderLogoHeight(horizontalSizeClass: horizontalSizeClass) * 1.5)
                    .scaleEffect(isShowingContent ? 1.0 : 0.8)
                    .opacity(isShowingContent ? 1.0 : 0.0)
                
                // Content will be injected below in the parent view
            }
            .padding(.top, 40)
        }
        .frame(height: 350)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                isShowingContent = true
            }
        }
    }
}
