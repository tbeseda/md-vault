import Foundation

/// How to react when the open file's path is touched on disk.
enum ExternalChangeAction: Equatable, Sendable {
    /// Disk matches what we last read or wrote: our own save echoing back.
    case ignoreEcho
    /// Disk changed and the buffer has no unsaved edits: take the disk content.
    case reload
    /// Disk changed to exactly the buffer's content: just mark the buffer clean.
    case adopt
    /// Disk changed under unsaved edits: surface the banner, touch nothing.
    case conflict
}

enum ExternalChange {
    /// Stateless echo suppression by content comparison. No tokens, no mtimes,
    /// no timeout races: it compares outcomes, not intents, so it is immune to
    /// coalesced events and late deliveries.
    static func determine(diskContent: String, lastSavedText: String, bufferText: String) -> ExternalChangeAction {
        if diskContent == lastSavedText { return .ignoreEcho }
        if bufferText == lastSavedText { return .reload }
        if diskContent == bufferText { return .adopt }
        return .conflict
    }
}
