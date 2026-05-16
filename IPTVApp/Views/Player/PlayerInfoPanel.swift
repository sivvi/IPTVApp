import UIKit
import SnapKit

/// Paged info panel with 4 tabs (流信息 / 节目单 / 频道 / 线路).
/// Stays visible when the control bar auto-hides; only hidden in fullscreen.
final class PlayerInfoPanel: UIView {

    // MARK: - Callbacks

    var onPageSelected: ((Int) -> Void)?

    // MARK: - Subviews

    private let tabBar = UIStackView()
    private let pageScrollView = UIScrollView()
    private let pageStack = UIStackView()

    private let pages: [PlayerInfoPageView] = (0..<4).map { _ in PlayerInfoPageView() }

    private let tabs: [PlayerInfoTab] = [
        PlayerInfoTab(icon: "info.circle", title: "流信息"),
        PlayerInfoTab(icon: "list.bullet.rectangle", title: "节目单"),
        PlayerInfoTab(icon: "tv", title: "频道"),
        PlayerInfoTab(icon: "antenna.radiowaves.left.and.right", title: "线路"),
    ]

    private var currentPage = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupTabBar()
        setupPages()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Setup

    private func setupTabBar() {
        tabBar.axis = .horizontal
        tabBar.distribution = .fillEqually
        tabBar.spacing = 12
        addSubview(tabBar)
        tabBar.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(60)
        }

        for (i, tab) in tabs.enumerated() {
            tab.tag = i
            tab.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabBar.addArrangedSubview(tab)
        }
    }

    private func setupPages() {
        pageScrollView.isPagingEnabled = true
        pageScrollView.showsHorizontalScrollIndicator = false
        pageScrollView.showsVerticalScrollIndicator = false
        pageScrollView.delegate = self
        pageScrollView.bounces = false
        addSubview(pageScrollView)
        pageScrollView.snp.makeConstraints { make in
            make.top.equalTo(tabBar.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
        }

        pageStack.axis = .horizontal
        pageStack.distribution = .fillEqually
        pageScrollView.addSubview(pageStack)
        pageStack.snp.makeConstraints { make in
            make.edges.height.equalToSuperview()
        }

        for page in pages {
            pageStack.addArrangedSubview(page)
            page.snp.makeConstraints { make in
                make.width.equalTo(pageScrollView.snp.width)
            }
        }
    }

    // MARK: - Public

    /// Show content on a specific page. Pass an empty rows array to show a loading/empty hint.
    func setContent(title: String, rows: [(String, String)], forPage pageIndex: Int) {
        guard pageIndex < pages.count else { return }
        pages[pageIndex].setContent(title: title, rows: rows)
    }

    /// Programmatically switch to a page.
    func selectPage(_ index: Int, animated: Bool = true) {
        guard index >= 0, index < pages.count else { return }
        updateTabSelection(index)
        let offset = CGPoint(x: CGFloat(index) * pageScrollView.bounds.width, y: 0)
        pageScrollView.setContentOffset(offset, animated: animated)
    }

    // MARK: - Actions

    @objc private func tabTapped(_ sender: UIButton) {
        selectPage(sender.tag)
    }

    private func updateTabSelection(_ index: Int) {
        currentPage = index
        for (i, tab) in tabs.enumerated() {
            tab.isSelectedState = (i == index)
        }
    }
}

// MARK: - UIScrollViewDelegate

extension PlayerInfoPanel: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        updateTabSelection(page)
        onPageSelected?(page)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        updateTabSelection(page)
        onPageSelected?(page)
    }
}

// MARK: - PlayerInfoTab

private final class PlayerInfoTab: UIButton {

    private let iconView = UIImageView()
    private let tabLabel = UILabel()

    var isSelectedState: Bool = false {
        didSet {
            backgroundColor = isSelectedState
                ? UIColor(hex: "#FF6B35").withAlphaComponent(0.3)
                : UIColor.white.withAlphaComponent(0.12)
            layer.borderColor = isSelectedState
                ? UIColor(hex: "#FF6B35").cgColor
                : UIColor.white.withAlphaComponent(0.2).cgColor
        }
    }

    init(icon: String, title: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor.white.withAlphaComponent(0.12)
        layer.cornerRadius = 10
        layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        layer.borderWidth = 0.5

        iconView.image = UIImage(systemName: icon)
        iconView.tintColor = UIColor(hex: "#FF6B35")
        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)

        tabLabel.text = title
        tabLabel.textColor = .white
        tabLabel.font = .systemFont(ofSize: 12, weight: .medium)
        tabLabel.textAlignment = .center
        addSubview(tabLabel)

        iconView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(10)
            make.width.height.equalTo(20)
        }

        tabLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(iconView.snp.bottom).offset(4)
            make.bottom.equalToSuperview().offset(-8)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - PlayerInfoPageView

final class PlayerInfoPageView: UIView {

    private let titleLabel = UILabel()
    private let contentStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        addSubview(titleLabel)

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.alignment = .fill
        addSubview(contentStack)

        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(12)
        }

        contentStack.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setContent(title: String, rows: [(String, String)]) {
        titleLabel.text = title
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (key, value) in rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fill
            row.alignment = .top
            row.spacing = 12
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)

            let keyLabel = UILabel()
            keyLabel.text = key
            keyLabel.font = .systemFont(ofSize: 13, weight: .medium)
            keyLabel.textColor = UIColor(hex: "#B2BEC3")
            keyLabel.setContentHuggingPriority(.required, for: .horizontal)

            let valueLabel = UILabel()
            valueLabel.text = value
            valueLabel.font = .systemFont(ofSize: 13)
            valueLabel.textColor = UIColor(hex: "#DFE6E9")
            valueLabel.numberOfLines = 0

            row.addArrangedSubview(keyLabel)
            row.addArrangedSubview(valueLabel)
            contentStack.addArrangedSubview(row)

            let sep = UIView()
            sep.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            sep.snp.makeConstraints { $0.height.equalTo(0.5) }
            contentStack.addArrangedSubview(sep)
        }
    }
}
