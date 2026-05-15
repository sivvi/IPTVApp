import UIKit
import Combine
import SnapKit

final class SettingsViewController: UIViewController {

    private let viewModel: SettingsViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private enum Section: Int, CaseIterable {
        case playback
        case channel
        case cache
        case appearance
        case about

        var header: String? {
            switch self {
            case .playback: return "播放设置"
            case .channel: return "频道管理"
            case .cache: return "缓存"
            case .appearance: return "外观"
            case .about: return "关于"
            }
        }
    }

    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        view.backgroundColor = UIColor(hex: "#FFF9F0")
        setupTableView()
        bindViewModel()
        viewModel.refreshStats()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.refreshStats()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = UIColor(hex: "#FFF9F0")
        tableView.register(SettingsToggleCell.self, forCellReuseIdentifier: "toggle")
        tableView.register(SettingsSelectionCell.self, forCellReuseIdentifier: "selection")
        tableView.register(SettingsActionCell.self, forCellReuseIdentifier: "action")
        tableView.register(SettingsInfoCell.self, forCellReuseIdentifier: "info")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func bindViewModel() {
        viewModel.$cacheSizeText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isViewLoaded, let section = self.sectionIndex(.cache) else { return }
                self.tableView.reloadSections([section], with: .none)
            }
            .store(in: &viewModel.cancellables)

        viewModel.errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                self?.present(alert, animated: true)
            }
            .store(in: &viewModel.cancellables)
    }

    private func sectionIndex(_ section: Section) -> Int? {
        Section.allCases.firstIndex(of: section)
    }

    // MARK: - Helpers

    private func presentQualityPicker() {
        let sheet = UIAlertController(title: "播放画质", message: nil, preferredStyle: .actionSheet)
        for quality in PlaybackQuality.allCases {
            let isCurrent = quality == viewModel.preferredQuality
            sheet.addAction(UIAlertAction(title: isCurrent ? "\(quality.rawValue) ✓" : quality.rawValue, style: .default) { [weak self] _ in
                self?.viewModel.preferredQuality = quality
                self?.reloadSection(.playback)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func presentEPGIntervalPicker() {
        let sheet = UIAlertController(title: "EPG自动更新", message: nil, preferredStyle: .actionSheet)
        for interval in EPGRefreshInterval.allCases {
            let isCurrent = interval == viewModel.epgRefreshInterval
            sheet.addAction(UIAlertAction(title: isCurrent ? "\(interval.rawValue) ✓" : interval.rawValue, style: .default) { [weak self] _ in
                self?.viewModel.epgRefreshInterval = interval
                self?.reloadSection(.channel)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func presentThemePicker() {
        let sheet = UIAlertController(title: "外观主题", message: nil, preferredStyle: .actionSheet)
        for theme in AppTheme.allCases {
            let isCurrent = theme == viewModel.theme
            sheet.addAction(UIAlertAction(title: isCurrent ? "\(theme.rawValue) ✓" : theme.rawValue, style: .default) { [weak self] _ in
                self?.viewModel.theme = theme
                self?.reloadSection(.appearance)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func presentClearCacheConfirmation() {
        let alert = UIAlertController(
            title: "清理缓存",
            message: "将清除EPG缓存和频道图片缓存，确定继续？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清理", style: .destructive) { [weak self] _ in
            self?.viewModel.clearCache()
        })
        present(alert, animated: true)
    }

    private func openAddPlaylist() {
        let vc = AddPlaylistViewController()
        vc.onPlaylistAdded = { [weak self] in
            self?.viewModel.refreshStats()
        }
        let nc = UINavigationController(rootViewController: vc)
        present(nc, animated: true)
    }

    private func openPlaylistManager() {
        let vc = PlaylistManagerViewController(viewModel: viewModel)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func reloadSection(_ section: Section) {
        guard let idx = sectionIndex(section) else { return }
        tableView.reloadSections([idx], with: .none)
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .playback: return 4
        case .channel: return 3
        case .cache: return 1
        case .appearance: return 1
        case .about: return 2
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)!.header
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = Section(rawValue: indexPath.section)!

        switch section {
        case .playback:
            return playbackCell(for: indexPath.row)
        case .channel:
            return channelCell(for: indexPath.row)
        case .cache:
            return cacheCell()
        case .appearance:
            return appearanceCell()
        case .about:
            return aboutCell(for: indexPath.row)
        }
    }

    // MARK: Cell builders

    private func playbackCell(for row: Int) -> UITableViewCell {
        switch row {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "toggle", for: indexPath(section: .playback, row: row)) as! SettingsToggleCell
            cell.configure(title: "硬件解码", value: viewModel.hardwareDecoding) { [weak self] on in
                self?.viewModel.hardwareDecoding = on
            }
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "selection", for: indexPath(section: .playback, row: row)) as! SettingsSelectionCell
            cell.configure(title: "播放画质", detail: viewModel.preferredQuality.rawValue)
            return cell
        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "toggle", for: indexPath(section: .playback, row: row)) as! SettingsToggleCell
            cell.configure(title: "后台播放", value: viewModel.backgroundPlayback) { [weak self] on in
                self?.viewModel.backgroundPlayback = on
            }
            return cell
        case 3:
            let cell = tableView.dequeueReusableCell(withIdentifier: "toggle", for: indexPath(section: .playback, row: row)) as! SettingsToggleCell
            cell.configure(title: "自动续播", value: viewModel.autoResume) { [weak self] on in
                self?.viewModel.autoResume = on
            }
            return cell
        default:
            return UITableViewCell()
        }
    }

    private func channelCell(for row: Int) -> UITableViewCell {
        switch row {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "action", for: indexPath(section: .channel, row: row)) as! SettingsActionCell
            cell.configure(title: "导入播放列表", icon: "square.and.arrow.down")
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "selection", for: indexPath(section: .channel, row: row)) as! SettingsSelectionCell
            cell.configure(title: "EPG自动更新", detail: viewModel.epgRefreshInterval.rawValue)
            return cell
        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "action", for: indexPath(section: .channel, row: row)) as! SettingsActionCell
            cell.configure(title: "管理播放源", icon: "list.bullet")
            return cell
        default:
            return UITableViewCell()
        }
    }

    private func cacheCell() -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "action", for: indexPath(section: .cache, row: 0)) as! SettingsActionCell
        cell.configure(title: "清理缓存", detail: viewModel.cacheSizeText, icon: "trash")
        return cell
    }

    private func appearanceCell() -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "selection", for: indexPath(section: .appearance, row: 0)) as! SettingsSelectionCell
        cell.configure(title: "主题", detail: viewModel.theme.rawValue)
        return cell
    }

    private func aboutCell(for row: Int) -> UITableViewCell {
        if row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "info", for: indexPath(section: .about, row: row)) as! SettingsInfoCell
            cell.configure(title: "版本", detail: viewModel.appVersion)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "action", for: indexPath(section: .about, row: row)) as! SettingsActionCell
            cell.configure(title: "反馈问题", icon: "envelope")
            return cell
        }
    }

    private func indexPath(section: Section, row: Int) -> IndexPath {
        IndexPath(row: row, section: sectionIndex(section)!)
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = Section(rawValue: indexPath.section)!

        switch section {
        case .playback:
            if indexPath.row == 1 { presentQualityPicker() }
        case .channel:
            if indexPath.row == 0 { openAddPlaylist() }
            else if indexPath.row == 1 { presentEPGIntervalPicker() }
            else if indexPath.row == 2 { openPlaylistManager() }
        case .cache:
            presentClearCacheConfirmation()
        case .appearance:
            presentThemePicker()
        case .about:
            if indexPath.row == 1 { openFeedback() }
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .playback:
            return indexPath.row == 1 // only quality picker is tappable
        case .about:
            return indexPath.row == 1 // only feedback is tappable
        case .channel, .cache, .appearance:
            return true
        }
    }

    private func openFeedback() {
        guard let url = URL(string: "mailto:feedback@iptvapp.example.com") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Cell Types

private final class SettingsToggleCell: UITableViewCell {

    private let toggle = UISwitch()
    private var onChange: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .white
        toggle.onTintColor = UIColor(hex: "#FF6B35")
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        accessoryView = toggle
        textLabel?.font = .systemFont(ofSize: 16)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, value: Bool, onChange: @escaping (Bool) -> Void) {
        textLabel?.text = title
        toggle.isOn = value
        self.onChange = onChange
    }

    @objc private func toggled() {
        onChange?(toggle.isOn)
    }
}

private final class SettingsSelectionCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
        backgroundColor = .white
        accessoryType = .disclosureIndicator
        textLabel?.font = .systemFont(ofSize: 16)
        detailTextLabel?.font = .systemFont(ofSize: 15)
        detailTextLabel?.textColor = UIColor(hex: "#636E72")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, detail: String) {
        textLabel?.text = title
        detailTextLabel?.text = detail
    }
}

private final class SettingsActionCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
        backgroundColor = .white
        textLabel?.font = .systemFont(ofSize: 16)
        detailTextLabel?.font = .systemFont(ofSize: 15)
        detailTextLabel?.textColor = UIColor(hex: "#636E72")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, detail: String? = nil, icon: String) {
        textLabel?.text = title
        detailTextLabel?.text = detail
        imageView?.image = UIImage(systemName: icon)?.withTintColor(UIColor(hex: "#FF6B35"), renderingMode: .alwaysOriginal)
        accessoryType = detail != nil ? .none : .disclosureIndicator
    }
}

private final class SettingsInfoCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
        backgroundColor = .white
        selectionStyle = .none
        textLabel?.font = .systemFont(ofSize: 16)
        detailTextLabel?.font = .systemFont(ofSize: 15)
        detailTextLabel?.textColor = UIColor(hex: "#B2BEC3")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, detail: String) {
        textLabel?.text = title
        detailTextLabel?.text = detail
    }
}

// MARK: - Playlist Manager Sub-screen

private final class PlaylistManagerViewController: UIViewController {

    private let vm: SettingsViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var playlists: [Playlist] = []

    init(viewModel: SettingsViewModel) {
        self.vm = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "播放源管理"
        view.backgroundColor = UIColor(hex: "#FFF9F0")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = UIColor(hex: "#FFF9F0")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        loadData()
    }

    private func loadData() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = (try? DatabaseManager.shared.fetchAllPlaylists()) ?? []
            DispatchQueue.main.async {
                self?.playlists = result
                self?.tableView.reloadData()
            }
        }
    }
}

extension PlaylistManagerViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        playlists.isEmpty ? 1 : playlists.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.backgroundColor = .white

        if playlists.isEmpty {
            cell.textLabel?.text = "暂无播放源"
            cell.textLabel?.textColor = UIColor(hex: "#B2BEC3")
            cell.accessoryType = .none
            cell.selectionStyle = .none
        } else {
            let p = playlists[indexPath.row]
            cell.textLabel?.text = p.name
            cell.textLabel?.textColor = UIColor(hex: "#2D3436")
            cell.detailTextLabel?.text = p.isDefault ? "默认" : nil
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        return cell
    }
}

extension PlaylistManagerViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !playlists.isEmpty else { return }
        let playlist = playlists[indexPath.row]
        presentOptions(for: playlist)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, !playlists.isEmpty else { return }
        let playlist = playlists[indexPath.row]
        do {
            try DatabaseManager.shared.deletePlaylist(id: playlist.id)
            playlists.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            vm.refreshStats()
        } catch {
            let alert = UIAlertController(title: nil, message: "删除失败: \(error.localizedDescription)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
    }

    private func presentOptions(for playlist: Playlist) {
        let sheet = UIAlertController(title: playlist.name, message: "来源: \(playlist.sourceUrl)", preferredStyle: .actionSheet)

        if !playlist.isDefault {
            sheet.addAction(UIAlertAction(title: "设为默认", style: .default) { [weak self] _ in
                try? DatabaseManager.shared.setDefaultPlaylist(id: playlist.id)
                self?.loadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }
}
