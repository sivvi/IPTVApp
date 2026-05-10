import UIKit
import SnapKit
import Combine

final class ChannelListViewController: BaseViewController<ChannelListViewModel> {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    private let refreshControl = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "直播"
        setupNavigationBar()
        setupTableView()
        setupSearchController()
        setupBindings()
        viewModel.loadChannels()
        viewModel.loadPlaylists()
    }

    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addPlaylistTapped)
        )
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ChannelCell.self, forCellReuseIdentifier: ChannelCell.reuseIdentifier)
        tableView.rowHeight = 76
        tableView.separatorColor = UIColor(hex: "#F1F2F6")
        tableView.refreshControl = refreshControl
        tableView.sectionIndexColor = UIColor(hex: "#FF6B35")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func setupSearchController() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索频道"
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }

    private func setupBindings() {
        viewModel.$groupedChannels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] channels in
                self?.tableView.reloadData()
                if channels.isEmpty {
                    self?.showEmptyState(
                        icon: "tv",
                        title: "还没有频道",
                        actionTitle: "添加播放源",
                        action: { [weak self] in self?.addPlaylistTapped() }
                    )
                } else {
                    self?.hideEmptyState()
                }
            }
            .store(in: &viewModel.cancellables)

        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPress)
    }

    @objc private func refreshTriggered() {
        viewModel.loadChannels()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }

    @objc private func addPlaylistTapped() {
        let addVC = AddPlaylistViewController()
        addVC.channelListViewModel = viewModel
        addVC.onPlaylistAdded = { [weak self] in
            self?.viewModel.loadChannels()
            self?.viewModel.loadPlaylists()
        }
        let nav = UINavigationController(rootViewController: addVC)
        present(nav, animated: true)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point) else { return }
        let channel = viewModel.groupedChannels[indexPath.section].channels[indexPath.row]

        let alert = UIAlertController(title: channel.name, message: nil, preferredStyle: .actionSheet)
        let favTitle = channel.isFavorite ? "取消收藏" : "收藏"
        alert.addAction(UIAlertAction(title: favTitle, style: .default) { [weak self] _ in
            self?.viewModel.toggleFavorite(channelId: channel.id)
        })
        alert.addAction(UIAlertAction(title: "分享", style: .default) { [weak self] _ in
            let activityVC = UIActivityViewController(activityItems: [channel.url], applicationActivities: nil)
            self?.present(activityVC, animated: true)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ChannelListViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.groupedChannels.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.groupedChannels[section].channels.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChannelCell.reuseIdentifier, for: indexPath) as! ChannelCell
        let channel = viewModel.groupedChannels[indexPath.section].channels[indexPath.row]
        cell.configure(channel: channel, currentProgram: viewModel.currentProgram(for: channel.id))
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        viewModel.groupedChannels[section].group
    }
}

// MARK: - UITableViewDelegate

extension ChannelListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let channel = viewModel.groupedChannels[indexPath.section].channels[indexPath.row]
        let playerVC = PlayerViewController(channel: channel)
        present(playerVC, animated: true)
    }
}

// MARK: - UISearchResultsUpdating

extension ChannelListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchQuery = searchController.searchBar.text ?? ""
    }
}
