import UIKit
import SnapKit

final class EPGChannelGridViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "节目指南"
        view.backgroundColor = UIColor(hex: "#FFF9F0")

        let placeholder = UILabel()
        placeholder.text = "节目指南 EPG"
        placeholder.textColor = UIColor(hex: "#B2BEC3")
        placeholder.font = .systemFont(ofSize: 17)
        view.addSubview(placeholder)
        placeholder.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
}
