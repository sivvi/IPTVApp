import UIKit
import SnapKit

final class EPGNowPlayingView: UIView {

    private let programTitleLabel = UILabel()
    private let timeLabel = UILabel()
    private let progressBar = UIView()
    private let progressFill = UIView()
    private let nextProgramLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        programTitleLabel.textColor = .white
        programTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        programTitleLabel.numberOfLines = 1
        addSubview(programTitleLabel)

        timeLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        addSubview(timeLabel)

        progressBar.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        progressBar.layer.cornerRadius = 1.5
        addSubview(progressBar)

        progressFill.backgroundColor = UIColor(hex: "#FF6B35")
        progressFill.layer.cornerRadius = 1.5
        progressBar.addSubview(progressFill)

        nextProgramLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        nextProgramLabel.font = .systemFont(ofSize: 11, weight: .regular)
        nextProgramLabel.numberOfLines = 1
        addSubview(nextProgramLabel)

        programTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalTo(timeLabel.snp.leading).offset(-8)
        }

        timeLabel.snp.makeConstraints { make in
            make.centerY.equalTo(programTitleLabel)
            make.trailing.equalToSuperview().offset(-16)
        }
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        progressBar.snp.makeConstraints { make in
            make.top.equalTo(programTitleLabel.snp.bottom).offset(6)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
            make.height.equalTo(3)
        }

        nextProgramLabel.snp.makeConstraints { make in
            make.top.equalTo(progressBar.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().offset(-8)
        }
    }

    func configure(epgId: String?) {
        guard let epgId, !epgId.isEmpty else {
            isHidden = true
            return
        }

        do {
            if let current = try EPGService.shared.fetchCurrentProgram(for: epgId) {
                programTitleLabel.text = current.title
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                timeLabel.text = "\(formatter.string(from: current.startTime))-\(formatter.string(from: current.endTime))"

                // Progress
                let total = current.endTime.timeIntervalSince(current.startTime)
                let elapsed = Date().timeIntervalSince(current.startTime)
                let ratio = total > 0 ? max(0, min(1, CGFloat(elapsed / total))) : 0
                progressFill.snp.remakeConstraints { make in
                    make.top.leading.bottom.equalToSuperview()
                    make.width.equalToSuperview().multipliedBy(ratio)
                }

                // Next program
                if let next = try EPGService.shared.fetchNextProgram(for: epgId) {
                    let nextFormatter = DateFormatter()
                    nextFormatter.dateFormat = "HH:mm"
                    nextProgramLabel.text = "接下来: \(next.title) (\(nextFormatter.string(from: next.startTime)))"
                    nextProgramLabel.isHidden = false
                } else {
                    nextProgramLabel.isHidden = true
                }

                isHidden = false
            } else {
                isHidden = true
            }
        } catch {
            isHidden = true
        }
    }

    func setVisible(_ visible: Bool, animated: Bool = true) {
        UIView.animate(withDuration: animated ? 0.25 : 0) {
            self.alpha = visible ? 1 : 0
        }
    }
}
