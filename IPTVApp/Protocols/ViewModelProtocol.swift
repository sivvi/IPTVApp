import Combine

protocol ViewModelProtocol: AnyObject {
    var isLoading: CurrentValueSubject<Bool, Never> { get }
    var errorMessage: PassthroughSubject<String, Never> { get }
    var cancellables: Set<AnyCancellable> { get set }
}
