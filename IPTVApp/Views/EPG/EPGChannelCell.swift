import UIKit
import SnapKit
import Kingfisher

final class EPGChannelCell: UITableViewCell {
    static let reuseIdentifier = "EPGChannelCell"

    private let logoImageView = UIImageView()
    private let nameLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor(hex: "#FFF9F0")
        contentView.backgroundColor = UIColor(hex: "#FFF9F0")

        let separator = UIView()
        separator.backgroundColor = UIColor(hex: "#F1F2F6")
        contentView.addSubview(separator)
        separator.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }

        logoImageView.contentMode = .scaleAspectFit
        logoImageView.clipsToBounds = true
        logoImageView.layer.cornerRadius = 10
        contentView.addSubview(logoImageView)
        logoImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(20)
        }

        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textColor = UIColor(hex: "#636E72")
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.leading.equalTo(logoImageView.snp.trailing).offset(6)
            make.trailing.equalToSuperview().offset(-4)
            make.centerY.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        logoImageView.kf.cancelDownloadTask()
        logoImageView.image = nil
        nameLabel.text = nil
    }

    func configure(channel: Channel) {
        nameLabel.text = channel.name
        if let logoUrl = channel.logoUrl, let url = URL(string: logoUrl) {
            logoImageView.kf.setImage(with: url, options: [.transition(.fade(0.2))])
        } else {
            logoImageView.image = UIImage(systemName: "tv")
        }
    }
}
