import UIKit
import SnapKit
import Combine
import AVKit

final class DevicePickerViewController: BaseViewController<DevicePickerViewModel> {

    var onDeviceSelected: ((DLNADevice) -> Void)?
    var onDismiss: (() -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let scanButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let airPlayRoutePickerView = AVRoutePickerView()

    private var localCancellables = Set<AnyCancellable>()

    override init(viewModel: DevicePickerViewModel = DevicePickerViewModel()) {
        super.init(viewModel: viewModel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "选择投屏设备"
        view.backgroundColor = UIColor(hex: "#FFF9F0")
        setupNavigationBar()
        setupTableView()
        setupAirPlaySection()
        bindViewModel()
        viewModel.startScan()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.stopScan()
        onDismiss?()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.tintColor = UIColor(hex: "#2D3436")
        navigationItem.leftBarButtonItem = closeButton

        scanButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        scanButton.tintColor = UIColor(hex: "#FF6B35")
        scanButton.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)

        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = UIColor(hex: "#FF6B35")

        let stack = UIStackView(arrangedSubviews: [activityIndicator, scanButton])
        stack.axis = .horizontal
        stack.spacing = 12
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: stack)
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(DeviceCell.self, forCellReuseIdentifier: DeviceCell.reuseIdentifier)
        tableView.backgroundColor = .clear
        tableView.rowHeight = 64
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func setupAirPlaySection() {
        airPlayRoutePickerView.activeTintColor = UIColor(hex: "#FF6B35")
        airPlayRoutePickerView.tintColor = UIColor(hex: "#636E72")
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.dlnaDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &localCancellables)

        viewModel.isScanning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scanning in
                if scanning {
                    self?.activityIndicator.startAnimating()
                } else {
                    self?.activityIndicator.stopAnimating()
                }
            }
            .store(in: &localCancellables)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func scanTapped() {
        viewModel.stopScan()
        viewModel.startScan()
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
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-20)
            make.height.equalTo(36)
            make.leading.greaterThanOrEqualToSuperview().offset(40)
        }

        UIView.animate(withDuration: 0.3) { label.alpha = 1 } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.5) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource

extension DevicePickerViewController: UITableViewDelegate, UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "DLNA 设备" : "AirPlay"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            let count = viewModel.dlnaDevices.value.count
            return count == 0 ? 1 : count
        }
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "AirPlay 设备"
            cell.imageView?.image = UIImage(systemName: "airplayvideo")
            cell.imageView?.tintColor = UIColor(hex: "#636E72")
            cell.accessoryView = airPlayRoutePickerView
            return cell
        }

        let devices = viewModel.dlnaDevices.value
        if devices.isEmpty {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = viewModel.isScanning.value ? "正在搜索..." : "未发现设备"
            cell.textLabel?.textColor = UIColor(hex: "#B2BEC3")
            cell.textLabel?.font = .systemFont(ofSize: 15)
            cell.selectionStyle = .none
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(withIdentifier: DeviceCell.reuseIdentifier, for: indexPath) as? DeviceCell else {
            return UITableViewCell()
        }
        let device = devices[indexPath.row]
        let isConnected = viewModel.selectedDevice.value?.id == device.id
        cell.configure(device: device, isConnected: isConnected)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else { return }
        let devices = viewModel.dlnaDevices.value
        guard !devices.isEmpty, indexPath.row < devices.count else { return }
        let device = devices[indexPath.row]
        viewModel.selectDevice(device)
        onDeviceSelected?(device)
    }
}
