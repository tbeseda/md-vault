import Foundation

enum ExternalChangeAction: Equatable, Sendable {
    case ignoreEcho
    case reload
    case adopt
    case conflict
}

enum ExternalChange {
    static func determine(diskContent: String, lastSavedText: String, bufferText: String) -> ExternalChangeAction {
        if diskContent == lastSavedText { return .ignoreEcho }
        if bufferText == lastSavedText { return .reload }
        if diskContent == bufferText { return .adopt }
        return .conflict
    }
}
