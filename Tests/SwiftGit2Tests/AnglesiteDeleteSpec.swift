//
//  AnglesiteDeleteSpec.swift
//  SwiftGit2Tests
//
//  Coverage for the three methods added on this fork for Anglesite-app#640's
//  processGitDelete conversion: remove(path:), headHasEntry(atPath:), restorePathFromHEAD(_:).
//  Builds its own repos from scratch (create → add → defaultSignature → commit) rather than the
//  zip-fixture machinery, since these are new, fork-specific additions.
//
//  .serialized: libgit2 isn't safe for uncoordinated concurrent use across threads (each test
//  here uses its own Repository/temp dir, so there's no shared mutable state between them, but
//  running them on Swift Testing's default parallel-thread pool crashed with SIGABRT deep in
//  libgit2 regardless — verified serialized execution is what actually needs).

import Foundation
import Testing
import SwiftGit2

@Suite("Anglesite delete support", .serialized) final class AnglesiteDeleteSpec {

    private func makeRepoWithOneCommittedFile(named fileName: String = "tracked.txt", contents: String = "hello") throws -> (repo: Repository, dir: URL) {
        _ = SwiftGit2Init()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftgit2-delete-spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let repo = try Repository.create(at: dir).get()
        try contents.write(to: dir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        try repo.add(path: fileName).get()
        let signature = Signature(name: "Test", email: "test@example.com")
        _ = try repo.commit(message: "initial", signature: signature).get()
        return (repo, dir)
    }

    @Test("headHasEntry(atPath:) is true for a committed file, false for an untracked one")
    func headHasEntryReflectsCommittedState() throws {
        let (repo, dir) = try makeRepoWithOneCommittedFile()
        #expect(repo.headHasEntry(atPath: "tracked.txt"))
        #expect(!repo.headHasEntry(atPath: "never-existed.txt"))

        // Staged but never committed: still not in HEAD.
        try "new".write(to: dir.appendingPathComponent("staged-only.txt"), atomically: true, encoding: .utf8)
        try repo.add(path: "staged-only.txt").get()
        #expect(!repo.headHasEntry(atPath: "staged-only.txt"))
    }

    @Test("headHasEntry(atPath:) is false on an unborn HEAD (zero commits)")
    func headHasEntryOnUnbornHEAD() throws {
        _ = SwiftGit2Init()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftgit2-delete-spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let repo = try Repository.create(at: dir).get()
        #expect(!repo.headHasEntry(atPath: "anything.txt"))
    }

    @Test("remove(path:) unstages and deletes the file from disk")
    func removeDeletesFromIndexAndDisk() throws {
        let (repo, dir) = try makeRepoWithOneCommittedFile()
        let fileURL = dir.appendingPathComponent("tracked.txt")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        try repo.remove(path: "tracked.txt").get()

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        // Still present in HEAD (not committed yet) — only the working tree/index changed.
        #expect(repo.headHasEntry(atPath: "tracked.txt"))
    }

    @Test("restorePathFromHEAD(_:) restores a removed file's content and re-stages it")
    func restorePathFromHEADUndoesRemove() throws {
        let (repo, dir) = try makeRepoWithOneCommittedFile(contents: "original content")
        let fileURL = dir.appendingPathComponent("tracked.txt")

        try repo.remove(path: "tracked.txt").get()
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        try repo.restorePathFromHEAD("tracked.txt").get()

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let restored = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(restored == "original content")

        // The rollback's whole point: a fresh remove+commit should now succeed again, proving
        // the index was un-staged back to matching HEAD, not just the working-tree file restored.
        try repo.remove(path: "tracked.txt").get()
        let signature = Signature(name: "Test", email: "test@example.com")
        let commit = try repo.commit(message: "remove tracked.txt", signature: signature).get()
        #expect(commit.parents.count == 1)
    }

    @Test("full delete-then-rollback sequence matches processGitDelete's contract shape")
    func fullDeleteRollbackSequence() throws {
        let (repo, dir) = try makeRepoWithOneCommittedFile(named: "unused.astro", contents: "<div></div>")
        let fileURL = dir.appendingPathComponent("unused.astro")

        // Precondition guard: HEAD must have the file before touching anything.
        #expect(repo.headHasEntry(atPath: "unused.astro"))

        try repo.remove(path: "unused.astro").get()
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        // Simulate the commit step failing (e.g. no identity, rejecting hook) by just not
        // committing, then rolling back exactly like processGitDelete's failure path does.
        try repo.restorePathFromHEAD("unused.astro").get()

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "<div></div>")
    }
}
