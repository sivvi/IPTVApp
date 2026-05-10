import UIKit
import SnapKit
import Kingfisher

final class ChannelCell: UITableViewCell {
    static let reuseIdentifier = "ChannelCell"

    private let logoImageView = UIImageView()
    private let nameLabel = UILabel()
    private let programLabel = UILabel()
    private let favoriteIcon = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .white
        selectionStyle = .none

        logoImageView.contentMode = .scaleAspectFill
        logoImageView.clipsToBounds = true
        logoImageView.layer.cornerRadius = 12
        logoImageView.backgroundColor = UIColor(hex: "#F1F2F6")

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = UIColor(hex: "#2D3436")

        programLabel.font = .systemFont(ofSize: 13)
        programLabel.textColor = UIColor(hex: "#636E72")

        favoriteIcon.image = UIImage(systemName: "star.fill")
        favoriteIcon.tintColor = UIColor(hex: "#FF6B35")
        favoriteIcon.isHidden = true

        contentView.addSubview(logoImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(programLabel)
        contentView.addSubview(favoriteIcon)

        logoImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(48)
        }
        nameLabel.snp.makeConstraints { make in
            make.leading.equalTo(logoImageView.snp.trailing).offset(12)
            make.top.equalToSuperview().offset(14)
            make.trailing.equalTo(favoriteIcon.snp.leading).offset(-8)
        }
        programLabel.snp.makeConstraints { make in
            make.leading.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(4)
            make.trailing.equalTo(nameLabel)
        }
        favoriteIcon.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }
    }

    func configure(channel: Channel, currentProgram: Program?) {
        nameLabel.text = channel.name
        programLabel.text = currentProgram?.title ?? "暂无节目信息"
        favoriteIcon.isHidden = !channel.isFavorite

        if let logoUrl = channel.logoUrl, let url = URL(string: logoUrl) {
            logoImageView.kf.setImage(
                with: url,
                placeholder: UIImage(systemName: "tv"),
                options: [.transition(.fade(0.2)), .cacheOriginalImage]
            )
        } else {
            logoImageView.image = UIImage(systemName: "tv")
        }
    }
}
