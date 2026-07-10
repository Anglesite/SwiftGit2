//
//  AnglesiteCommitSpec.swift
//  SwiftGit2Tests
//
//  Regression coverage for the unborn-HEAD fix in Repository.commit(message:signature:)
//  (Anglesite-app#640 / SwiftGit2/SwiftGit2#174), and specifically for a bug found in code
//  review of that fix: `git_reference_name_to_id` never writes to its `out` parameter on ANY
//  failure path (see refs.c), so checking `git_oid_iszero(&parentID)` was true for every
//  failure, not just a genuinely unborn HEAD — silently forking history instead of failing on
//  unrelated errors. Fixed to key off GIT_ENOTFOUND specifically.
//
//  .serialized: see AnglesiteDeleteSpec — libgit2 isn't safe for uncoordinated concurrent use.

import Foundation
import Testing
import SwiftGit2

@Suite("Anglesite commit support", .serialized) final class AnglesiteCommitSpec {

    private func makeEmptyRepo() throws -> (repo: Repository, dir: URL) {
        _ = SwiftGit2Init()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftgit2-commit-spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let repo = try Repository.create(at: dir).get()
        return (repo, dir)
    }

    @Test("creates a parentless root commit on a genuinely unborn HEAD")
    func commitOnUnbornHEAD() throws {
        let (repo, dir) = try makeEmptyRepo()
        try "hello".write(to: dir.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        try repo.add(path: "hello.txt").get()
        let signature = Signature(name: "Test", email: "test@example.com")

        let commit = try repo.commit(message: "first", signature: signature).get()

        #expect(commit.parents.isEmpty)
    }

    @Test("fails rather than silently forking history when HEAD resolution fails for a non-unborn reason")
    func commitFailsOnNonUnbornHEADResolutionError() throws {
        let (repo, dir) = try makeEmptyRepo()
        try "hello".write(to: dir.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        try repo.add(path: "hello.txt").get()
        let signature = Signature(name: "Test", email: "test@example.com")

        // First commit succeeds on the genuinely-unborn HEAD, establishing real history.
        let first = try repo.commit(message: "first", signature: signature).get()
        #expect(first.parents.isEmpty)

        // Break HEAD resolution for a reason that has nothing to do with being unborn: make
        // refs/heads unreadable, so resolving "HEAD" -> "refs/heads/master" fails with a
        // permission error, not GIT_ENOTFOUND. `add`/`git_index_write_tree` only touch the index
        // and .git/objects, so they're unaffected — this isolates the failure to exactly the ref
        // resolution step inside `commit(message:signature:)`.
        let refsHeadsDir = dir.appendingPathComponent(".git/refs/heads")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: refsHeadsDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: refsHeadsDir.path) }

        try "more".write(to: dir.appendingPathComponent("second.txt"), atomically: true, encoding: .utf8)
        try repo.add(path: "second.txt").get()

        let result = repo.commit(message: "second", signature: signature)

        #expect(result.error != nil)
    }
}
