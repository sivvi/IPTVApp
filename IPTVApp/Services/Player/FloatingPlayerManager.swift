import UIKit
import Combine

final class FloatingPlayerManager {

    static let shared = FloatingPlayerManager()

    private var floatWindow: UIWindow?
    private var floatView: FloatingPlayerView?
    private var channel: Channel?
    private var playerService: PlayerServiceProtocol?
    private var cancellables = Set<AnyCancellable>()

    var isActive: Bool { floatWindow != nil }

    private init() {}

    // MARK: - Public

    func enterFloatingMode(
        playerService: PlayerServiceProtocol,
        videoView: UIView,
        channel: Channel
    ) {
        guard floatWindow == nil else { return }

        self.playerService = playerService
        self.channel = channel

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 100
        window.backgroundColor = .clear

        let size = CGSize(width: 300, height: 170)
        // Screen bounds may be landscape when invoked from fullscreen; always use
        // portrait orientation dimensions so the window stays on-screen after the
        // dismiss triggers the rotation back to portrait.
        let bounds = scene.screen.bounds
        let pw = min(bounds.width, bounds.height)
        let ph = max(bounds.width, bounds.height)
        let originX = pw - size.width - 12
        let originY = ph - ph / 3
        let floatView = FloatingPlayerView(frame: CGRect(origin: CGPoint(x: originX, y: originY), size: size))
        floatView.attachVideo(videoView)
        floatView.isPlaying = playerService.state.value.isPlaying

        floatView.onClose = { [weak self] in
            self?.dismiss()
        }
        floatView.onExpand = { [weak self] in
            self?.expand()
        }
        floatView.onPlayPauseTapped = { [weak self] in
            self?.togglePlayPause()
        }

        playerService.state
            .receive(on: DispatchQueue.main)
            .sink { state in
                floatView.isPlaying = state.isPlaying
            }
            .store(in: &cancellables)

        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(floatView)
        window.isHidden = false
        floatView.layoutIfNeeded()

        self.floatWindow = window
        self.floatView = floatView
    }

    func dismiss() {
        guard let floatView else { return }
        floatView.detachVideo()
        floatView.removeFromSuperview()
        floatWindow?.isHidden = true
        floatWindow = nil
        self.floatView = nil
        playerService?.stop()
        playerService = nil
        channel = nil
        cancellables.removeAll()
    }

    func togglePlayPause() {
        guard let service = playerService else { return }
        if service.state.value.isPlaying {
            service.pause()
        } else {
            service.resume()
        }
    }

    private func expand() {
        guard let playerService, let channel, let floatView else { return }

        let videoView = floatView.detachVideo()
        floatView.removeFromSuperview()
        floatWindow?.isHidden = true
        floatWindow = nil
        self.floatView = nil

        let svc = playerService
        let ch = channel
        self.playerService = nil
        self.channel = nil
        cancellables.removeAll()

        let vc = PlayerViewController(channel: ch, renderer: videoView, service: svc)
        topViewController()?.present(vc, animated: true)
    }

    // MARK: - Helpers

    private func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }
            .first?.rootViewController
        if let nav = root as? UINavigationController { return topViewController(nav.visibleViewController) }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController { return topViewController(selected) }
        if let presented = root?.presentedViewController { return topViewController(presented) }
        return root
    }
}
