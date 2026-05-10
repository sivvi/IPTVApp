import UIKit
import Combine
import SnapKit

class BaseViewController<VM: ViewModelProtocol>: UIViewController {
    let viewModel: VM
    private var loadingView: UIActivityIndicatorView?
    private let emptyStateView = EmptyStateView()

    init(viewModel: VM) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: "#FFF9F0")
        view.addSubview(emptyStateView)
        emptyStateView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        setupBindings()
    }

    private func setupBindings() {
        viewModel.isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                loading ? self?.showLoading() : self?.hideLoading()
            }
            .store(in: &viewModel.cancellables)

        viewModel.errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.showToast(message)
            }
            .store(in: &viewModel.cancellables)
    }

    func showLoading() {
        guard loadingView == nil else { return }
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.center = view.center
        indicator.startAnimating()
        view.addSubview(indicator)
        loadingView = indicator
    }

    func hideLoading() {
        loadingView?.removeFromSuperview()
        loadingView = nil
    }

    func showEmptyState(icon: String = "tv", title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        emptyStateView.configure(icon: icon, title: title, actionTitle: actionTitle, action: action)
        emptyStateView.isHidden = false
    }

    func hideEmptyState() {
        emptyStateView.isHidden = true
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
        }

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn) {
            label.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: .curveEaseOut) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }
}
