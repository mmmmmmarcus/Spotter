import Foundation

enum SelectionToolsState: Equatable, Sendable {
    case idle
    case failed(String)
}
