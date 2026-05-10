import UIKit
import SnapKit
import Combine

final class FavoritesViewController: BaseViewController<FavoritesViewModel> {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "收藏"
        setupTableView()
        setupBindings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadFavorites()
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ChannelCell.self, forCellReuseIdentifier: ChannelCell.reuseIdentifier)
        tableView.rowHeight = 76
        tableView.separatorColor = UIColor(hex: "#F1F2F6")
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func setupBindings() {
        viewModel.$favoriteChannels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] channels in
                self?.tableView.reloadData()
                if channels.isEmpty {
                    self?.showEmptyState(icon: "star", title: "还没有收藏频道", actionTitle: nil, action: nil)
                } else {
                    self?.hideEmptyState()
                }
            }
            .store(in: &viewModel.cancellables)

        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
    }

    @objc private func refreshTriggered() {
        viewModel.loadFavorites()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }
}

// MARK: - UITableViewDataSource

extension FavoritesViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.favoriteChannels.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChannelCell.reuseIdentifier, for: indexPath) as! ChannelCell
        let channel = viewModel.favoriteChannels[indexPath.row]
        cell.configure(channel: channel, currentProgram: nil, health: nil)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension FavoritesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        let unfavorite = UIContextualAction(style: .destructive, title: "取消收藏") { [weak self] _, _, completion in
            let channel = self?.viewModel.favoriteChannels[indexPath.row]
            if let id = channel?.id {
                self?.viewModel.unfavorite(channelId: id)
            }
            completion(true)
        }
        unfavorite.backgroundColor = UIColor(hex: "#FF6B35")
        return UISwipeActionsConfiguration(actions: [unfavorite])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let channel = viewModel.favoriteChannels[indexPath.row]
        let playerVC = PlayerViewController(channel: channel)
        present(playerVC, animated: true)
    }
}
