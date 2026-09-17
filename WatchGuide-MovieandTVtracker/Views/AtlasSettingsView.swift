//
//  AtlasSettingsView.swift
//  WatchGuide-MovieandTVtracker
//
//  Everything the user controls about their assistant: who Atlas is, what it's
//  allowed to do, and what it remembers. Memory is listed item by item and can
//  be deleted individually — an assistant that quietly accumulates notes about
//  someone is only acceptable if they can see and remove them.
//

import SwiftUI

struct AtlasSettingsView: View {
    @AppStorage(AtlasPersona.storageKey) private var personaRaw = AtlasPersona.default.rawValue
    @AppStorage(AtlasPersona.userNameKey) private var userName = ""
    @AppStorage(AtlasProactiveEngine.dailyBriefingKey) private var dailyBriefing = false
    #if !os(tvOS)
    @AppStorage(AtlasHUDModifier.enabledKey) private var hudEnabled = true
    #endif
    @AppStorage(AtlasVoice.storageKey) private var voiceName = AtlasVoice.defaultVoice.rawValue

    @ObservedObject private var memory = AtlasMemoryStore.shared
    @ObservedObject private var actions = AtlasActionCenter.shared
    @ObservedObject private var proactive = AtlasProactiveEngine.shared

    @State private var showForgetAllConfirm = false

    private var persona: AtlasPersona {
        AtlasPersona(rawValue: personaRaw) ?? .default
    }

    var body: some View {
        Form {
            personalitySection
            presenceSection
            capabilitiesSection
            memorySection
        }
        .navigationTitle("Atlas")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Personality

    private var personalitySection: some View {
        Section {
            ForEach(AtlasPersona.allCases) { option in
                Button {
                    personaRaw = option.rawValue
                    // Follow the persona's voice unless the user has picked one
                    // themselves — switching to Butler shouldn't leave a bubbly
                    // voice behind on the first change.
                    voiceName = option.suggestedVoiceName
                    proactive.refresh()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: option.sfSymbol)
                            .font(.system(size: 16))
                            .foregroundStyle(option.accentColor)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(option.blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if option == persona {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            TextField("What should Atlas call you?", text: $userName)
                #if !os(tvOS)
                .textInputAutocapitalization(.words)
                #endif
        } header: {
            Text("Personality")
        } footer: {
            Text("Changes how Atlas talks in both chat and voice. Picking a personality also switches to its matching voice.")
        }
    }

    // MARK: - Presence

    private var presenceSection: some View {
        Section {
            #if !os(tvOS)
            Toggle("Floating Atlas button", isOn: $hudEnabled)
            #endif

            Toggle("Daily briefing", isOn: $dailyBriefing)
                .onChange(of: dailyBriefing) { _, _ in
                    #if canImport(UserNotifications) && !os(tvOS)
                    Task { await proactive.syncDailyBriefingNotification() }
                    #endif
                }
        } header: {
            Text("Presence")
        } footer: {
            Text("The floating button opens Atlas from any screen — tap to chat, hold for voice. The daily briefing sends one notification each morning when something on your list is out or waiting.")
        }
    }

    // MARK: - Capabilities

    private var capabilitiesSection: some View {
        Section {
            Toggle("Let Atlas control the app", isOn: $actions.isEnabled)
        } header: {
            Text("Actions")
        } footer: {
            Text("Atlas can add titles to your watchlist, mark things watched, and open screens when you ask. Everything it does is listed under its reply. With this off, Atlas can still talk about your library but can't change it.")
        }
    }

    // MARK: - Memory

    private var memorySection: some View {
        Section {
            Toggle("Remember things about me", isOn: $memory.isEnabled)

            if memory.memories.isEmpty {
                Text("Nothing remembered yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(AtlasMemoryStore.Kind.allCases) { kind in
                    let items = memory.memories(of: kind)
                    if !items.isEmpty {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: kind.sfSymbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(item.text)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            #if !os(tvOS)
                            .swipeActions {
                                Button("Forget", role: .destructive) {
                                    memory.forget(id: item.id)
                                }
                            }
                            #endif
                        }
                    }
                }

                Button("Forget everything", role: .destructive) {
                    showForgetAllConfirm = true
                }
                .confirmationDialog(
                    "Forget everything Atlas has learned about you?",
                    isPresented: $showForgetAllConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Forget everything", role: .destructive) { memory.forgetAll() }
                    Button("Cancel", role: .cancel) {}
                }
            }
        } header: {
            Text("Memory")
        } footer: {
            Text("Memories are stored only on this device and are never uploaded. Swipe any one to delete it.")
        }
    }
}

#Preview {
    NavigationStack {
        AtlasSettingsView()
    }
}
