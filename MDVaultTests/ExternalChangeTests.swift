import Testing
@testable import MDVault

/// The full decision matrix for external changes to the open file.
struct ExternalChangeTests {
    @Test func untouchedDiskWithCleanBufferIsEcho() {
        #expect(ExternalChange.determine(diskContent: "a", lastSavedText: "a", bufferText: "a") == .ignoreEcho)
    }

    @Test func untouchedDiskWithDirtyBufferIsEcho() {
        #expect(ExternalChange.determine(diskContent: "a", lastSavedText: "a", bufferText: "a edited") == .ignoreEcho)
    }

    @Test func changedDiskWithCleanBufferReloads() {
        #expect(ExternalChange.determine(diskContent: "agent edit", lastSavedText: "a", bufferText: "a") == .reload)
    }

    @Test func changedDiskMatchingDirtyBufferAdopts() {
        #expect(ExternalChange.determine(diskContent: "same edit", lastSavedText: "a", bufferText: "same edit") == .adopt)
    }

    @Test func changedDiskUnderDirtyBufferConflicts() {
        #expect(ExternalChange.determine(diskContent: "agent edit", lastSavedText: "a", bufferText: "my edit") == .conflict)
    }
}
