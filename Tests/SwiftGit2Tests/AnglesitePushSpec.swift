//
//  AnglesitePushSpec.swift
//  SwiftGit2Tests
//
//  Coverage for the Anglesite backup-path additions (Anglesite-app#653): `addAll()`
//  (`git add -A` parity — additions, modifications, AND deletions), `aheadBehind(local:upstream:)`
//  (the `git rev-list --count` replacement), `push(remoteName:refspec:credentials:)`
//  (`git_remote_push` with per-ref rejection reporting), and the `bare:` flag on
//  `Repository.create(at:)` these tests need for local push targets.
//
//  .serialized: see AnglesiteDeleteSpec — libgit2 isn't safe for uncoordinated concurrent use.

import Foundation
import Testing
import SwiftGit2

@Suite("Anglesite push support", .serialized) final class AnglesitePushSpec {

    private let signature = Signature(name: "Test", email: "test@example.com")

    private func makeTempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgit2-push-spec-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Working repo with one root commit containing `hello.txt`. `contents` must differ between
    /// repos that need *distinct* histories: two repos committing the same tree + message +
    /// author within the same second produce byte-identical commits with the SAME OID, and a
    /// "divergent" push of an identical commit is a no-op, not a rejection.
    private func makeRepoWithCommit(contents: String = "hello") throws -> (repo: Repository, dir: URL, first: Commit) {
        _ = SwiftGit2Init()
        let dir = try makeTempDir("work")
        let repo = try Repository.create(at: dir).get()
        try contents.write(to: dir.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        try repo.add(path: "hello.txt").get()
        let commit = try repo.commit(message: "first", signature: signature).get()
        return (repo, dir, commit)
    }

    private func commitFile(_ name: String, contents: String, message: String, in repo: Repository, dir: URL) throws -> Commit {
        try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        try repo.add(path: name).get()
        return try repo.commit(message: message, signature: signature).get()
    }

    // MARK: create(at:bare:)

    @Test("create(at:bare:) makes a bare repository that reports itself as bare")
    func createBareRepository() throws {
        _ = SwiftGit2Init()
        let dir = try makeTempDir("bare")
        let repo = try Repository.create(at: dir, bare: true).get()
        // A bare repo has no working directory — HEAD lives directly in `dir`.
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("HEAD").path))
        _ = repo
    }

    // MARK: addAll()

    @Test("addAll() stages additions, modifications, and deletions like `git add -A`")
    func addAllStagesEverything() throws {
        let (repo, dir, _) = try makeRepoWithCommit()

        // Second tracked file so we can delete one and modify the other.
        _ = try commitFile("doomed.txt", contents: "delete me", message: "add doomed", in: repo, dir: dir)

        // Untracked addition, tracked modification, tracked deletion.
        try "new".write(to: dir.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        try "hello v2".write(to: dir.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("doomed.txt"))

        try repo.addAll().get()
        _ = try repo.commit(message: "add -A parity", signature: signature).get()

        #expect(repo.headHasEntry(atPath: "new.txt"))
        #expect(repo.headHasEntry(atPath: "hello.txt"))
        #expect(!repo.headHasEntry(atPath: "doomed.txt"), "deletion must stage — plain git_index_add_all leaves removed files in the index")
        // Nothing should remain to report: the working tree matches HEAD exactly.
        let status = try repo.status().get()
        #expect(status.isEmpty)
    }

    // MARK: aheadBehind(local:upstream:)

    @Test("aheadBehind(local:upstream:) counts commits in each direction")
    func aheadBehindCounts() throws {
        let (repo, dir, first) = try makeRepoWithCommit()
        let second = try commitFile("two.txt", contents: "2", message: "second", in: repo, dir: dir)
        let third = try commitFile("three.txt", contents: "3", message: "third", in: repo, dir: dir)

        #expect(try repo.aheadBehind(local: third.oid, upstream: first.oid).get() == (ahead: 2, behind: 0))
        #expect(try repo.aheadBehind(local: first.oid, upstream: third.oid).get() == (ahead: 0, behind: 2))
        #expect(try repo.aheadBehind(local: second.oid, upstream: second.oid).get() == (ahead: 0, behind: 0))
    }

    // MARK: push(remoteName:refspec:credentials:)

    @Test("push updates the remote branch ref to the local HEAD commit")
    func pushUpdatesRemoteRef() throws {
        let (repo, dir, first) = try makeRepoWithCommit()
        let remoteDir = try makeTempDir("origin")
        _ = try Repository.create(at: remoteDir, bare: true).get()

        try repo.addRemote(named: "origin", url: remoteDir.absoluteString).get()
        try repo.push(remoteName: "origin", refspec: "refs/heads/master:refs/heads/master").get()

        let remoteRepo = try Repository.at(remoteDir).get()
        let pushedRef = try remoteRepo.reference(named: "refs/heads/master").get()
        #expect(pushedRef.oid == first.oid)

        // A fast-forward follow-up push moves the same ref again.
        let second = try commitFile("two.txt", contents: "2", message: "second", in: repo, dir: dir)
        try repo.push(remoteName: "origin", refspec: "refs/heads/master:refs/heads/master").get()
        let movedRef = try remoteRepo.reference(named: "refs/heads/master").get()
        #expect(movedRef.oid == second.oid)
    }

    @Test("push reports a non-fast-forward rejection as an error, not silent success")
    func pushRejectsNonFastForward() throws {
        // Two unrelated histories pushing the same branch: the second push cannot
        // fast-forward and must surface the per-ref rejection from the receiving side.
        let (repoA, _, _) = try makeRepoWithCommit(contents: "history A")
        let (repoB, _, _) = try makeRepoWithCommit(contents: "history B")
        let remoteDir = try makeTempDir("origin")
        _ = try Repository.create(at: remoteDir, bare: true).get()

        _ = try repoA.addRemote(named: "origin", url: remoteDir.absoluteString).get()
        _ = try repoB.addRemote(named: "origin", url: remoteDir.absoluteString).get()

        try repoA.push(remoteName: "origin", refspec: "refs/heads/master:refs/heads/master").get()
        let result = repoB.push(remoteName: "origin", refspec: "refs/heads/master:refs/heads/master")

        #expect(result.error != nil)
        // And the rejection must have left the remote ref where A put it.
        let remoteRepo = try Repository.at(remoteDir).get()
        let refAfter = try remoteRepo.reference(named: "refs/heads/master").get()
        #expect(refAfter.oid == repoA.HEAD().value?.oid)
    }

    @Test("push against a remote name that doesn't exist fails with a lookup error")
    func pushUnknownRemoteFails() throws {
        let (repo, _, _) = try makeRepoWithCommit()
        let result = repo.push(remoteName: "nonexistent", refspec: "refs/heads/master:refs/heads/master")
        #expect(result.error != nil)
    }
}
