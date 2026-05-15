import UIKit

final class AppCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []
    let navigationController = UINavigationController()
    private let window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func start() {
        let tabBarController = UITabBarController()
        tabBarController.tabBar.tintColor = UIColor(hex: "#FF6B35")
        tabBarController.tabBar.unselectedItemTintColor = UIColor(hex: "#B2BEC3")
        tabBarController.tabBar.backgroundColor = .white

        let channelListVM = ChannelListViewModel()
        let liveVC = ChannelListViewController(viewModel: channelListVM)
        let liveNC = UINavigationController(rootViewController: liveVC)
        liveNC.tabBarItem = UITabBarItem(
            title: "直播",
            image: UIImage(systemName: "tv"),
            selectedImage: UIImage(systemName: "tv.fill")
        )

        let epgNC = UINavigationController(rootViewController: EPGChannelGridViewController())
        epgNC.tabBarItem = UITabBarItem(
            title: "节目",
            image: UIImage(systemName: "calendar"),
            selectedImage: UIImage(systemName: "calendar.fill")
        )

        let favoritesVM = FavoritesViewModel()
        let favoritesVC = FavoritesViewController(viewModel: favoritesVM)
        let favoritesNC = UINavigationController(rootViewController: favoritesVC)
        favoritesNC.tabBarItem = UITabBarItem(
            title: "收藏",
            image: UIImage(systemName: "star"),
            selectedImage: UIImage(systemName: "star.fill")
        )

        let settingsVM = SettingsViewModel()
        let settingsVC = SettingsViewController(viewModel: settingsVM)
        let settingsNC = UINavigationController(rootViewController: settingsVC)
        settingsNC.tabBarItem = UITabBarItem(
            title: "设置",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )

        tabBarController.viewControllers = [liveNC, epgNC, favoritesNC, settingsNC]
        navigationController.setViewControllers([tabBarController], animated: false)
        navigationController.isNavigationBarHidden = true

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
    }
}
