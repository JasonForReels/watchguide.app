//
//  CreditsView.swift
//  WatchGuide-MovieandTVtracker
//
//  Credits page acknowledging data sources and partnerships.
//

import SwiftUI

struct CreditsView: View {
    
    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        40
        #else
        24
        #endif
    }
    
    private var horizontalInset: CGFloat {
        #if os(tvOS)
        80
        #else
        16
        #endif
    }
    
    private var cardCornerRadius: CGFloat {
        #if os(tvOS)
        24
        #else
        18
        #endif
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: sectionSpacing) {
                headerSection
                
                VStack(spacing: 14) {
                    nordVPNCard
                    fanArtCard
                    movieOfTheNightCard
                    theMovieDBCard
                    theTVDBCard
                    omdbCard
                }
                .padding(.horizontal, horizontalInset)
                
                Spacer(minLength: 40)
            }
            .padding(.top, 12)
        }
        .navigationTitle("Credits")
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("Powered By")
                .font(.title2)
                .fontWeight(.bold)
            Text("WatchGuide is made possible by these services")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalInset)
    }
    
    // MARK: - NordVPN
    
    private var nordVPNCard: some View {
        CreditCard(cornerRadius: cardCornerRadius) {
            HStack(spacing: 10) {
                Text("In Partnership with")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Image("NordVPNLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 24)
            }
        }
    }
    
    // MARK: - FanArt.tv
    
    private var fanArtCard: some View {
        CreditCard(cornerRadius: cardCornerRadius) {
            HStack(spacing: 12) {
                Image("FanArt.tv logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 30)
                
                Text("FanArt.tv")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
        }
    }
    
    // MARK: - MovieOfTheNight
    
    private var movieOfTheNightCard: some View {
        CreditCard(cornerRadius: cardCornerRadius) {
            Text("MovieOfTheNight")
                .font(.headline)
                .fontWeight(.semibold)
        }
    }
    
    // MARK: - TheMovieDB
    
    private var theMovieDBCard: some View {
        CreditCard(cornerRadius: cardCornerRadius) {
            Image("TheMovieDB")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 20)
        }
    }
    
    // MARK: - TheTVDB
    
    private var theTVDBCard: some View {
        CreditCard(cornerRadius: cardCornerRadius) {
            HStack(spacing: 12) {
                Image("TheTVDB")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 24)
                
                Text("TheTVDB")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
        }
    }
    
    // MARK: - OMDB
    
    private var omdbCard: some View {
        CreditCard(cornerRadius: cardCornerRadius) {
            Text("OMDb")
                .font(.headline)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Credit Card Container

private struct CreditCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content
    
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif
    
    var body: some View {
        HStack {
            Spacer()
            content
            Spacer()
        }
        .padding(.vertical, cardVerticalPadding)
        .padding(.horizontal, 20)
        #if os(tvOS)
        .tvOSPanelStyle(
            cornerRadius: cornerRadius,
            fillOpacity: isFocused ? 0.12 : 0.08,
            strokeOpacity: isFocused ? 0.24 : 0.12
        )
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        #else
        .modifier(LiquidGlassRoundedRect(cornerRadius: cornerRadius))
        #endif
    }
    
    private var cardVerticalPadding: CGFloat {
        #if os(tvOS)
        28
        #else
        18
        #endif
    }
}

#Preview {
    NavigationStack {
        CreditsView()
    }
}
