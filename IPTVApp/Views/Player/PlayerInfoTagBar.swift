import UIKit
import SnapKit

final class PlayerInfoTagBar: UIView {

    var onStreamInfoTapped: (() -> Void)?
    var onProgramListTapped: (() -> Void)?
    var onChannelTapped: (() -> Void)?
    var onSourceTapped: (() -> Void)?

    private let streamInfoTag = TagButton(icon: "info.circle", title: "流信息")
    private let programListTag = TagButton(icon: "list.bullet.rectangle", title: "节目单")
    private let channelTag = TagButton(icon: "tv", title: "频道")
    private let sourceTag = TagButton(icon: "antenna.radiowaves.left.and.right", title: "线路")

    private var allTags: [TagButton] { [streamInfoTag, programListTag, channelTag, sourceTag] }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let stack = UIStackView(arrangedSubviews: [streamInfoTag, programListTag, channelTag, sourceTag])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(24)
        }

        streamInfoTag.addTarget(self, action: #selector(streamInfoAction), for: .touchUpInside)
        programListTag.addTarget(self, action: #selector(programListAction), for: .touchUpInside)
        channelTag.addTarget(self, action: #selector(channelAction), for: .touchUpInside)
        sourceTag.addTarget(self, action: #selector(sourceAction), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func selectTag(at index: Int) {
        for (i, tag) in allTags.enumerated() {
            tag.isSelectedState = (i == index)
        }
    }

    @objc private func streamInfoAction() {
        selectTag(at: 0)
        onStreamInfoTapped?()
    }
    @objc private func programListAction() {
        selectTag(at: 1)
        onProgramListTapped?()
    }
    @objc private func channelAction() {
        selectTag(at: 2)
        onChannelTapped?()
    }
    @objc private func sourceAction() {
        selectTag(at: 3)
        onSourceTapped?()
    }
}

// MARK: - Tag Button

private final class TagButton: UIButton {

    private let iconView = UIImageView()
    private let tagLabel = UILabel()

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

        tagLabel.text = title
        tagLabel.textColor = .white
        tagLabel.font = .systemFont(ofSize: 12, weight: .medium)
        tagLabel.textAlignment = .center
        addSubview(tagLabel)

        iconView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(10)
            make.width.height.equalTo(20)
        }

        tagLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(iconView.snp.bottom).offset(4)
            make.bottom.equalToSuperview().offset(-8)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
