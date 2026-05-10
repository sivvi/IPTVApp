import Foundation
import Combine

final class EPGViewModel: BaseViewModel {

    @Published var channelPrograms: [(channel: Channel, programs: [Program])] = []
    @Published var selectedDate: Date = Date()

    private var allChannels: [Channel] = []

    override init() {
        super.init()
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

        let epgChannels = allChannels.filter { $0.epgId != nil && !$0.epgId!.isEmpty }
        guard !epgChannels.isEmpty else {
            channelPrograms = []
            return
        }

        let channelIds = epgChannels.map { $0.epgId! }

        do {
            let programsByChannel = try EPGService.shared.fetchPrograms(
                for: channelIds,
                date: selectedDate
            )

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            channelPrograms = epgChannels.compactMap { channel in
                let epgId = channel.epgId!
                let programs = programsByChannel[epgId] ?? []
                // Only include channels that are either in favorites or have EPG data
                guard channel.isFavorite || !programs.isEmpty else { return nil }
                // For past dates, always show if programs exist; for today, include favorites even without programs
                let isToday = calendar.isDate(selectedDate, inSameDayAs: today)
                if !isToday && programs.isEmpty { return nil }
                return (channel: channel, programs: programs)
            }
        } catch {
            errorMessage.send("加载节目失败: \(error.localizedDescription)")
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
