import UIKit
import SnapKit
import Combine

final class ChannelListViewController: BaseViewController<ChannelListViewModel> {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let refreshControl = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "直播"
        setupNavigationBar()
        setupTableView()
        setupSearchBar()
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
        tableView.keyboardDismissMode = .onDrag
    }

    private func setupSearchBar() {
        searchBar.placeholder = "搜索频道"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none

        // Fixed search bar above the table — stays visible when scrolling
        view.addSubview(searchBar)
        view.addSubview(tableView)

        searchBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(searchBar.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
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

        viewModel.$streamHealth
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let groups = viewModel.groupedChannels
                for indexPath in tableView.indexPathsForVisibleRows ?? [] {
                    guard indexPath.section < groups.count,
                          indexPath.row < groups[indexPath.section].channels.count,
                          let cell = tableView.cellForRow(at: indexPath) as? ChannelCell else { continue }
                    let channel = groups[indexPath.section].channels[indexPath.row]
                    cell.updateHealth(viewModel.health(for: channel.id))
                }
            }
            .store(in: &viewModel.cancellables)

        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPress)
    }

    @objc private func refreshTriggered() {
        viewModel.loadChannels()
        viewModel.refreshStreamHealth()
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

// MARK: - UISearchBarDelegate

extension ChannelListViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel.searchQuery = searchText
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
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
        let health = viewModel.health(for: channel.id)
        cell.configure(channel: channel, currentProgram: viewModel.currentProgram(for: channel.id), health: health)
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
        searchBar.resignFirstResponder()
        let channel = viewModel.groupedChannels[indexPath.section].channels[indexPath.row]
        let playerVC = PlayerViewController(channel: channel)
        present(playerVC, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let groups = viewModel.groupedChannels
        guard indexPath.section < groups.count,
              indexPath.row < groups[indexPath.section].channels.count else { return }
        let channel = groups[indexPath.section].channels[indexPath.row]
        viewModel.startHealthCheck(for: channel.id)
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // indexPath may be stale after reloadData — bounds-check against current data
        let groups = viewModel.groupedChannels
        guard indexPath.section < groups.count,
              indexPath.row < groups[indexPath.section].channels.count else { return }
        let channel = groups[indexPath.section].channels[indexPath.row]
        viewModel.cancelHealthCheck(for: channel.id)
    }
}
