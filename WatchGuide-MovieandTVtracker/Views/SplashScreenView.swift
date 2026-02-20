//
//  SplashScreenView.swift
//  WatchGuide-MovieandTVtracker
//
//  Animated video splash screen that works on all devices (iPhone, iPad, all orientations)
//

import SwiftUI
import AVFoundation
import AVKit

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var fadeOut: Double = 1.0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if isActive {
            ContentView()
                .transition(.opacity)
        } else {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                SplashVideoPlayer {
                    finishSplash()
                }
                .ignoresSafeArea()
            }
            .opacity(fadeOut)
            .onAppear {
                // Safety fallback: if video never triggers onFinished, skip after 8s
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                    finishSplash()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // If app goes to background during splash, finish immediately
                if newPhase == .background {
                    finishSplash()
                }
            }
            #if !os(tvOS)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            #endif
        }
    }

    private func finishSplash() {
        guard !isActive else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            fadeOut = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation {
                isActive = true
            }
        }
    }
}

// MARK: - Video Player (UIKit wrapper)
/// Plays the bundled MP4 once, filling the entire screen on every device,
/// then calls `onFinished` so the app can transition.
struct SplashVideoPlayer: UIViewControllerRepresentable {
    var onFinished: () -> Void

    func makeUIViewController(context: Context) -> SplashVideoViewController {
        let vc = SplashVideoViewController()
        vc.onFinished = onFinished
        return vc
    }

    func updateUIViewController(_ uiViewController: SplashVideoViewController, context: Context) {}
}

final class SplashVideoViewController: UIViewController {
    var onFinished: (() -> Void)?

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var observer: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var hasFinished = false

    #if !os(tvOS)
    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let url = Bundle.main.url(
            forResource: "C891E0F4-DF6C-4689-8EC3-865E5943F026_users_3e430e6b-9132-4628-92a7-dd0ab3746f5f_generated_d571b124-cd61-44c0-b7dc-c5a336ebaad6_generated_video",
            withExtension: "mp4"
        ) else {
            // Video not found – skip straight to app
            triggerFinish()
            return
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = false
        self.player = avPlayer

        let layer = AVPlayerLayer(player: avPlayer)
        layer.videoGravity = .resizeAspectFill  // fills every screen edge-to-edge
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        self.playerLayer = layer

        // Listen for playback end
        observer = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.triggerFinish()
        }

        // Observe for errors using modern KVO so we don't get stuck
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                DispatchQueue.main.async {
                    self?.triggerFinish()
                }
            }
        }

        avPlayer.play()
    }

    private func triggerFinish() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinished?()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Keep layer perfectly sized on rotation / resize / multitasking
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = view.bounds
        CATransaction.commit()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.playerLayer?.frame = CGRect(origin: .zero, size: size)
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.pause()
        cleanup()
    }

    private func cleanup() {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
    }

    deinit {
        cleanup()
    }
}

#Preview {
    SplashScreenView()
}
