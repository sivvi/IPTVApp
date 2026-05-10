import UIKit
import SnapKit

final class EPGTimelineView: UIView, UIScrollViewDelegate {

    var onProgramTapped: ((Program) -> Void)?
    var onVerticalScroll: ((CGPoint) -> Void)?

    private(set) var contentScrollView = UIScrollView()

    private let headerScrollView = UIScrollView()

    private let slotWidth: CGFloat = 60
    private let rowHeight: CGFloat = 60
    private let headerHeight: CGFloat = 30

    private let timeLineColor = UIColor(hex: "#FF6B35")
    private var timeSlots: [Date] = []
    private var channelCount = 0
    private var allPrograms: [(channel: Channel, programs: [Program])] = []

    private var currentTimeLine: UIView?
    private var timer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    private func setupViews() {
        headerScrollView.showsVerticalScrollIndicator = false
        headerScrollView.showsHorizontalScrollIndicator = false
        headerScrollView.bounces = false
        headerScrollView.backgroundColor = UIColor(hex: "#DFE6E9")
        addSubview(headerScrollView)

        contentScrollView.delegate = self
        contentScrollView.showsVerticalScrollIndicator = true
        contentScrollView.showsHorizontalScrollIndicator = true
        contentScrollView.bounces = true
        contentScrollView.backgroundColor = UIColor(hex: "#FFF9F0")
        addSubview(contentScrollView)

        headerScrollView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(headerHeight)
        }

        contentScrollView.snp.makeConstraints { make in
            make.top.equalTo(headerScrollView.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }

        // Sync horizontal scrolling: header follows content
        contentScrollView.addObserver(self, forKeyPath: "contentOffset", options: .new, context: nil)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentScrollView.addGestureRecognizer(tap)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "contentOffset", let offset = change?[.newKey] as? CGPoint {
            headerScrollView.contentOffset = CGPoint(x: offset.x, y: 0)
        }
    }

    // MARK: - Configure

    func configure(timeSlots: [Date], programs: [(channel: Channel, programs: [Program])]) {
        self.timeSlots = timeSlots
        self.allPrograms = programs
        self.channelCount = programs.count

        renderHeader()
        renderPrograms()
        addCurrentTimeLine()
        startTimeLineTimer()

        let totalWidth = CGFloat(timeSlots.count) * slotWidth
        let totalHeight = CGFloat(channelCount) * rowHeight
        headerScrollView.contentSize = CGSize(width: totalWidth, height: headerHeight)
        contentScrollView.contentSize = CGSize(width: totalWidth, height: totalHeight)

        scrollToCurrentTime(animated: false)
    }

    private func renderHeader() {
        headerScrollView.subviews.forEach { $0.removeFromSuperview() }

        let calendar = Calendar.current
        for (i, slot) in timeSlots.enumerated() {
            let minute = calendar.component(.minute, from: slot)
            guard minute == 0 else { continue }

            let hour = calendar.component(.hour, from: slot)
            let label = UILabel()
            label.text = String(format: "%02d:00", hour)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = UIColor(hex: "#636E72")
            label.textAlignment = .center
            label.frame = CGRect(x: CGFloat(i) * slotWidth, y: 0, width: slotWidth * 2, height: headerHeight)
            headerScrollView.addSubview(label)
        }
    }

    private func renderPrograms() {
        contentScrollView.subviews.forEach { $0.removeFromSuperview() }
        currentTimeLine = nil

        let categoryColors: [String: String] = [
            "新闻": "#E74C3C",
            "体育": "#27AE60",
            "电影": "#3498DB",
            "电视剧": "#9B59B6",
            "综艺": "#F39C12",
            "纪录片": "#1ABC9C",
            "少儿": "#E91E63",
            "音乐": "#00BCD4",
        ]

        for (row, item) in allPrograms.enumerated() {
            for program in item.programs {
                guard let startIdx = slotIndex(for: program.startTime),
                      let endIdx = slotIndex(for: program.endTime) else { continue }

                let x = CGFloat(startIdx) * slotWidth
                let y = CGFloat(row) * rowHeight
                let w = max(CGFloat(endIdx - startIdx) * slotWidth, 4)
                let h = rowHeight - 4

                let block = UIView(frame: CGRect(x: x, y: y + 2, width: w, height: h))
                let colorHex = categoryColors[program.category ?? ""] ?? "#B2BEC3"
                block.backgroundColor = UIColor(hex: colorHex).withAlphaComponent(0.85)
                block.layer.cornerRadius = 4
                block.clipsToBounds = true
                block.tag = row * 10000 + (startIdx)

                let titleLabel = UILabel()
                titleLabel.text = program.title
                titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
                titleLabel.textColor = .white
                titleLabel.numberOfLines = 2
                titleLabel.frame = CGRect(x: 4, y: 2, width: w - 8, height: h - 4)
                block.addSubview(titleLabel)

                contentScrollView.addSubview(block)
            }

            // Row separator
            let separator = UIView(frame: CGRect(x: 0, y: CGFloat(row + 1) * rowHeight - 0.5, width: contentScrollView.contentSize.width, height: 0.5))
            separator.backgroundColor = UIColor(hex: "#F1F2F6")
            contentScrollView.addSubview(separator)
        }
    }

    private func addCurrentTimeLine() {
        let calendar = Calendar.current
        let now = Date()
        guard calendar.isDate(now, inSameDayAs: timeSlots.first ?? now) else { return }

        let startOfDay = calendar.startOfDay(for: now)
        let elapsed = now.timeIntervalSince(startOfDay)
        let totalSlots = Double(timeSlots.count)
        let slotDuration: TimeInterval = 1800 // 30 min
        let position = elapsed / slotDuration
        guard position >= 0, position <= totalSlots else { return }

        let x = CGFloat(position) * slotWidth
        let line = UIView(frame: CGRect(x: x, y: 0, width: 2, height: CGFloat(channelCount) * rowHeight))
        line.backgroundColor = timeLineColor
        contentScrollView.addSubview(line)
        currentTimeLine = line
    }

    private func startTimeLineTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.currentTimeLine?.removeFromSuperview()
            self?.addCurrentTimeLine()
        }
    }

    private func scrollToCurrentTime(animated: Bool) {
        let calendar = Calendar.current
        let now = Date()
        guard calendar.isDate(now, inSameDayAs: timeSlots.first ?? now) else { return }

        let startOfDay = calendar.startOfDay(for: now)
        let elapsed = now.timeIntervalSince(startOfDay)
        let x = CGFloat(elapsed / 1800) * slotWidth - contentScrollView.bounds.width / 2
        let maxX = contentScrollView.contentSize.width - contentScrollView.bounds.width
        contentScrollView.setContentOffset(CGPoint(x: max(0, min(maxX, x)), y: 0), animated: animated)
    }

    // MARK: - Tap Handling

    @objc private func handleTap(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: contentScrollView)
        let row = Int(point.y / rowHeight)
        guard row < allPrograms.count else { return }

        let slotIdx = Int(point.x / slotWidth)
        guard slotIdx < timeSlots.count else { return }

        let slotTime = timeSlots[slotIdx]
        let programs = allPrograms[row].programs
        if let program = programs.first(where: { $0.startTime <= slotTime && $0.endTime > slotTime }) {
            onProgramTapped?(program)
        }
    }

    // MARK: - Helpers

    private func slotIndex(for date: Date) -> Int? {
        guard let first = timeSlots.first else { return nil }
        let diff = date.timeIntervalSince(first)
        let idx = Int(round(diff / 1800))
        guard idx >= 0, idx < timeSlots.count else { return nil }
        return idx
    }
}

// MARK: - UIScrollViewDelegate

extension EPGTimelineView {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === contentScrollView else { return }
        onVerticalScroll?(scrollView.contentOffset)
    }
}
