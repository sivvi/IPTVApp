import UIKit

final class FloatingPlayerManager {

    static let shared = FloatingPlayerManager()

    private var floatWindow: UIWindow?
    private var floatView: FloatingPlayerView?
    private var channel: Channel?
    private var playerService: PlayerServiceProtocol?

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
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        let size = CGSize(width: 160, height: 90)
        let originX = scene.screen.bounds.width - size.width - 12
        let originY = scene.screen.bounds.height - scene.screen.bounds.height / 3
        let floatView = FloatingPlayerView(frame: CGRect(origin: CGPoint(x: originX, y: originY), size: size))
        floatView.attachVideo(videoView)

        floatView.onClose = { [weak self] in
            self?.dismiss()
        }
        floatView.onExpand = { [weak self] in
            self?.expand()
        }

        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(floatView)
        window.isHidden = false
        // Force layout so videoContainer gets correct bounds from floatView's frame,
        // which triggers SnapKit on the attached video view to fill the container.
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

        // Present full-screen player with the existing renderer
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
