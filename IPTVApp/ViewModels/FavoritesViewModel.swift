import Foundation

final class FavoritesViewModel: BaseViewModel {

    @Published var favoriteChannels: [Channel] = []

    func loadFavorites() {
        isLoading.send(true)
        defer { isLoading.send(false) }

        do {
            favoriteChannels = try DatabaseManager.shared.fetchFavoriteChannels()
        } catch {
            errorMessage.send("加载收藏失败: \(error.localizedDescription)")
        }
    }

    func unfavorite(channelId: String) {
        do {
            try DatabaseManager.shared.toggleFavorite(channelId: channelId)
            loadFavorites()
        } catch {
            errorMessage.send("操作失败: \(error.localizedDescription)")
        }
    }
}
