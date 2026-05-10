import UIKit
import SnapKit

final class SettingsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        view.backgroundColor = UIColor(hex: "#FFF9F0")

        let placeholder = UILabel()
        placeholder.text = "设置"
        placeholder.textColor = UIColor(hex: "#B2BEC3")
        placeholder.font = .systemFont(ofSize: 17)
        view.addSubview(placeholder)
        placeholder.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
}
