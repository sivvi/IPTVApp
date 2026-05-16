import UIKit
import SnapKit
import UniformTypeIdentifiers

final class AddPlaylistViewController: UIViewController {

    var onPlaylistAdded: (() -> Void)?
    var channelListViewModel: ChannelListViewModel?

    private let urlTextField = UITextField()
    private let nameTextField = UITextField()
    private let epgUrlTextField = UITextField()
    private let addButton = UIButton(type: .system)
    private let importButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "添加播放源"
        view.backgroundColor = UIColor(hex: "#FFF9F0")
        setupUI()
    }

    private func setupUI() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "取消", style: .plain, target: self, action: #selector(dismissSelf)
        )

        urlTextField.placeholder = "播放列表 URL (http://...)"
        urlTextField.borderStyle = .roundedRect
        urlTextField.keyboardType = .URL
        urlTextField.autocapitalizationType = .none

        nameTextField.placeholder = "播放列表名称（可选）"
        nameTextField.borderStyle = .roundedRect

        epgUrlTextField.placeholder = "EPG 节目单 URL（可选，含 url-tvg 时自动填充）"
        epgUrlTextField.borderStyle = .roundedRect
        epgUrlTextField.keyboardType = .URL
        epgUrlTextField.autocapitalizationType = .none

        addButton.setTitle("添加", for: .normal)
        addButton.setTitleColor(.white, for: .normal)
        addButton.backgroundColor = UIColor(hex: "#FF6B35")
        addButton.layer.cornerRadius = 12
        addButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        importButton.setTitle("从文件导入", for: .normal)
        importButton.setTitleColor(UIColor(hex: "#FF6B35"), for: .normal)
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        let stack = UIStackView(arrangedSubviews: [
            urlTextField, nameTextField, epgUrlTextField, addButton, importButton, activityIndicator, errorLabel
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(24, after: importButton)
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(24)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        addButton.snp.makeConstraints { $0.height.equalTo(48) }
    }

    @objc private func addTapped() {
        guard let urlString = urlTextField.text?.trimmingCharacters(in: .whitespaces),
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            showError("请输入有效的URL")
            return
        }

        errorLabel.isHidden = true
        activityIndicator.startAnimating()
        addButton.isEnabled = false

        let vm = channelListViewModel ?? ChannelListViewModel()

        let manualEpgUrl = epgUrlTextField.text?.trimmingCharacters(in: .whitespaces)
        let manualEpgURL = manualEpgUrl.flatMap { !$0.isEmpty ? URL(string: $0) : nil }
        vm.loadPlaylist(from: url, manualEpgURL: manualEpgURL)

        vm.isLoading
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] loading in
                if !loading {
                    self?.activityIndicator.stopAnimating()
                    self?.addButton.isEnabled = true
                    self?.onPlaylistAdded?()
                    self?.dismiss(animated: true)
                }
            }
            .store(in: &vm.cancellables)

        vm.errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.showError(msg)
                self?.activityIndicator.stopAnimating()
                self?.addButton.isEnabled = true
            }
            .store(in: &vm.cancellables)
    }

    @objc private func importTapped() {
        let types: [UTType] = [.init(filenameExtension: "m3u")!, .init(filenameExtension: "m3u8")!]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
    }
}

extension AddPlaylistViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let vm = channelListViewModel ?? ChannelListViewModel()
        vm.loadPlaylistFromLocalFile(url: url)

        vm.isLoading
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] loading in
                if !loading {
                    self?.onPlaylistAdded?()
                    self?.dismiss(animated: true)
                }
            }
            .store(in: &vm.cancellables)
    }
}
