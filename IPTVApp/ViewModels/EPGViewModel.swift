import Foundation
import Combine

final class EPGViewModel: BaseViewModel {

    @Published var channelPrograms: [(channel: Channel, programs: [Program])] = []
    @Published var selectedDate: Date = Date()
    @Published var searchQuery: String = ""

    private var allChannels: [Channel] = []
    private var allChannelPrograms: [(channel: Channel, programs: [Program])] = []

    override init() {
        super.init()
        $searchQuery
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyFilter()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public

    func loadPrograms() {
        isLoading.send(true)
        defer { isLoading.send(false) }

        do {
            allChannels = try DatabaseManager.shared.fetchAllChannels()
        } catch {
            errorMessage.send("加载频道失败: \(error.localizedDescription)")
            return
        }

        guard !allChannels.isEmpty else {
            allChannelPrograms = []
            channelPrograms = []
            return
        }

        // Load EPG channel id → display-name mapping for name-based fallback
        let epgChannelMap: [String: String] = {
            guard let data = UserDefaults.standard.data(forKey: "epg_channel_map"),
                  let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return map
        }()

        // Build a reverse map: channel name → epg channel id (lowercased for fuzzy matching)
        var nameToEpgId: [String: String] = [:]
        for (epgId, displayName) in epgChannelMap {
            nameToEpgId[displayName.lowercased()] = epgId
        }

        // For each channel, resolve its effective EPG id
        var channelEffectiveEpgId: [(channel: Channel, effectiveEpgId: String?)] = []
        var allEpgIds: Set<String> = []

        for channel in allChannels {
            if let epgId = channel.epgId, !epgId.isEmpty {
                channelEffectiveEpgId.append((channel, epgId))
                allEpgIds.insert(epgId)
            } else if let matchedId = nameToEpgId[channel.name.lowercased()] {
                channelEffectiveEpgId.append((channel, matchedId))
                allEpgIds.insert(matchedId)
            } else {
                channelEffectiveEpgId.append((channel, nil))
            }
        }

        guard !allEpgIds.isEmpty else {
            allChannelPrograms = []
            channelPrograms = []
            return
        }

        do {
            let programsByChannel = try EPGService.shared.fetchPrograms(
                for: Array(allEpgIds),
                date: selectedDate
            )

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            allChannelPrograms = channelEffectiveEpgId.compactMap { item in
                let programs: [Program]
                if let epgId = item.effectiveEpgId {
                    programs = programsByChannel[epgId] ?? []
                } else {
                    programs = []
                }
                guard item.channel.isFavorite || !programs.isEmpty else { return nil }
                let isToday = calendar.isDate(selectedDate, inSameDayAs: today)
                if !isToday && programs.isEmpty { return nil }
                return (channel: item.channel, programs: programs)
            }
            applyFilter()
        } catch {
            errorMessage.send("加载节目失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Search

    private func applyFilter() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            channelPrograms = allChannelPrograms
        } else {
            channelPrograms = allChannelPrograms.filter {
                $0.channel.name.localizedCaseInsensitiveContains(query) ||
                ($0.channel.group ?? "").localizedCaseInsensitiveContains(query)
            }
        }
    }

    func timeSlots(for date: Date) -> [Date] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return (0..<48).map { calendar.date(byAdding: .minute, value: $0 * 30, to: startOfDay)! }
    }

    func goToToday() {
        selectedDate = Date()
        loadPrograms()
    }

    func goToPreviousDay() {
        let calendar = Calendar.current
        if let prev = calendar.date(byAdding: .day, value: -1, to: selectedDate) {
            selectedDate = prev
            loadPrograms()
        }
    }

    func goToNextDay() {
        let calendar = Calendar.current
        if let next = calendar.date(byAdding: .day, value: 1, to: selectedDate) {
            selectedDate = next
            loadPrograms()
        }
    }

    var dateTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "今天"
        } else if calendar.isDateInTomorrow(selectedDate) {
            return "明天"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "昨天"
        }
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: selectedDate)
    }

    // MARK: - Helpers

    func program(at channelIndex: Int, for slotTime: Date) -> Program? {
        guard channelIndex < channelPrograms.count else { return nil }
        let programs = channelPrograms[channelIndex].programs
        return programs.first { program in
            program.startTime <= slotTime && program.endTime > slotTime
        }
    }
}
