import UIKit
import SnapKit
import Combine

final class EPGChannelGridViewController: UIViewController {

    private let viewModel = EPGViewModel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let timelineView = EPGTimelineView()
    private let dateLabel = UILabel()
    private let searchController = UISearchController(searchResultsController: nil)
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "节目指南"
        view.backgroundColor = UIColor(hex: "#FFF9F0")
        setupNavigationBar()
        setupSearch()
        setupViews()
        setupBindings()
        viewModel.loadPrograms()
    }

    private func setupNavigationBar() {
        let prevButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(prevDay)
        )
        let nextButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.right"),
            style: .plain,
            target: self,
            action: #selector(nextDay)
        )
        navigationItem.leftBarButtonItems = [prevButton, nextButton]

        dateLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        dateLabel.textColor = UIColor(hex: "#2D3436")
        dateLabel.textAlignment = .center
        navigationItem.titleView = dateLabel
    }

    private func setupSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索频道"
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }

    private func setupViews() {
        view.addSubview(tableView)
        view.addSubview(timelineView)

        tableView.register(EPGChannelCell.self, forCellReuseIdentifier: EPGChannelCell.reuseIdentifier)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 60
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.backgroundColor = UIColor(hex: "#FFF9F0")

        timelineView.onProgramTapped = { [weak self] program in
            self?.showProgramDetail(program)
        }

        // Sync timeline vertical scroll back to channel list (right → left)
        timelineView.onVerticalScroll = { [weak self] offset in
            guard let self else { return }
            let sv = self.timelineView.contentScrollView
            guard sv.isDragging || sv.isDecelerating else { return }
            self.tableView.contentOffset.y = offset.y
        }

        layoutViews()
    }

    private func layoutViews() {
        let leftWidth: CGFloat = 100

        tableView.snp.remakeConstraints { make in
            make.top.leading.bottom.equalTo(view.safeAreaLayoutGuide)
            make.width.equalTo(leftWidth)
        }

        timelineView.snp.remakeConstraints { make in
            make.top.trailing.bottom.equalTo(view.safeAreaLayoutGuide)
            make.leading.equalTo(tableView.snp.trailing)
        }
    }

    private func setupBindings() {
        viewModel.$channelPrograms
            .receive(on: DispatchQueue.main)
            .sink { [weak self] programs in
                self?.tableView.reloadData()
                self?.updateTimeline(programs: programs)
                if programs.isEmpty {
                    self?.showEmptyOverlay()
                } else {
                    self?.hideEmptyOverlay()
                }
            }
            .store(in: &cancellables)

        viewModel.$selectedDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dateLabel.text = self?.viewModel.dateTitle
            }
            .store(in: &cancellables)

        viewModel.isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                loading ? self?.showLoading() : self?.hideLoading()
            }
            .store(in: &cancellables)

        viewModel.errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.showToast(msg)
            }
            .store(in: &cancellables)
    }

    private func updateTimeline(programs: [(channel: Channel, programs: [Program])]) {
        let slots = viewModel.timeSlots(for: viewModel.selectedDate)
        timelineView.configure(timeSlots: slots, programs: programs)
    }

    // MARK: - Actions

    @objc private func prevDay() {
        viewModel.goToPreviousDay()
    }

    @objc private func nextDay() {
        viewModel.goToNextDay()
    }

    // MARK: - Program Detail

    private func showProgramDetail(_ program: Program) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let message = """
        时间: \(formatter.string(from: program.startTime)) - \(formatter.string(from: program.endTime))
        分类: \(program.category ?? "未分类")

        \(program.description ?? "暂无简介")
        """

        let alert = UIAlertController(title: program.title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))

        // Find the channel for this program and offer to play
        if let channel = viewModel.channelPrograms.first(where: { $0.channel.epgId == program.channelId })?.channel {
            alert.addAction(UIAlertAction(title: "播放", style: .default) { [weak self] _ in
                let playerVC = PlayerViewController(channel: channel)
                self?.present(playerVC, animated: true)
            })
        }

        present(alert, animated: true)
    }

    // MARK: - Empty State

    private var emptyLabel: UILabel?

    private func showEmptyOverlay() {
        guard emptyLabel == nil else { return }
        let label = UILabel()
        label.text = "暂无节目数据"
        label.textColor = UIColor(hex: "#B2BEC3")
        label.font = .systemFont(ofSize: 15)
        label.textAlignment = .center
        label.numberOfLines = 0
        view.addSubview(label)
        label.snp.makeConstraints { $0.center.equalToSuperview() }
        emptyLabel = label
    }

    private func hideEmptyOverlay() {
        emptyLabel?.removeFromSuperview()
        emptyLabel = nil
    }

    // MARK: - Loading

    private var loadingIndicator: UIActivityIndicatorView?

    private func showLoading() {
        guard loadingIndicator == nil else { return }
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.center = view.center
        indicator.startAnimating()
        view.addSubview(indicator)
        loadingIndicator = indicator
    }

    private func hideLoading() {
        loadingIndicator?.removeFromSuperview()
        loadingIndicator = nil
    }

    private func showToast(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.alpha = 0
        view.addSubview(label)
        label.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-32)
            make.height.equalTo(36)
            make.leading.greaterThanOrEqualToSuperview().offset(40)
        }
        UIView.animate(withDuration: 0.3) { label.alpha = 1 } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }
}

// MARK: - TableView

extension EPGChannelGridViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.channelPrograms.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: EPGChannelCell.reuseIdentifier, for: indexPath) as! EPGChannelCell
        let item = viewModel.channelPrograms[indexPath.row]
        cell.configure(channel: item.channel)
        return cell
    }
}

// MARK: - Scroll Sync

extension EPGChannelGridViewController {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        timelineView.contentScrollView.contentOffset.y = scrollView.contentOffset.y
    }
}

// MARK: - UISearchResultsUpdating

extension EPGChannelGridViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchQuery = searchController.searchBar.text ?? ""
    }
}
