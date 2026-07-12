//
//  AnglesiteRobustnessSpec.swift
//  SwiftGit2Tests
//
//  Coverage for the robustness hardening around the Anglesite-app use case (in-process git in a
//  sandboxed app, operating on user-owned repositories): malformed user-editable state must
//  surface as `Result` failures, never crashes; `fetch` must carry credentials; and libgit2
//  initialization must be automatic for every `Repository` entry point.
//
//  .serialized: see AnglesiteDeleteSpec — libgit2 isn't safe for uncoordinated concurrent use.

import Foundation
import Testing
import SwiftGit2

@Suite("Anglesite robustness hardening", .serialized) final class AnglesiteRobustnessSpec {

    private let signature = Signature(name: "Test", email: "test@example.com")

    private func makeTempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgit2-robustness-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Remote without a fetch URL

    // Deliberately no SwiftGit2Init() here (unlike the other Anglesite specs): Repository.create
    // is expected to bootstrap libgit2 itself now. Suite ordering can't isolate this perfectly —
    // another suite may have initialized the library first — but running this file alone
    // exercises it for real.
    @Test("remote(named:) on a pushurl-only remote returns a failure instead of crashing")
    func urllessRemoteFails() throws {
        let dir = try makeTempDir("urlless")
        let repo = try Repository.create(at: dir).get()

        // A hand-edited config can declare a remote with only a pushurl; git_remote_url is then
        // NULL. The old force-unwrapping Remote(pointer) initializer crashed the process here.
        let config = dir.appendingPathComponent(".git/config")
        let existing = try String(contentsOf: config, encoding: .utf8)
        try (existing + "\n[remote \"broken\"]\n\tpushurl = https://example.invalid/broken.git\n")
            .write(to: config, atomically: true, encoding: .utf8)

        // Depending on the libgit2 version, the lookup itself may refuse a URL-less remote — the
        // contract under test is only "a failure, not a crash".
        guard case .failure = repo.remote(named: "broken") else {
            Issue.record("expected a failure for a remote with no fetch URL")
            return
        }
    }

    // MARK: fetch(_:credentials:)

    @Test("fetch(_:credentials:) fetches from a local remote")
    func fetchFromLocalRemote() throws {
        // Upstream repo with one commit…
        let upstreamDir = try makeTempDir("upstream")
        let upstream = try Repository.create(at: upstreamDir).get()
        try "hello".write(to: upstreamDir.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        try upstream.add(path: "hello.txt").get()
        _ = try upstream.commit(message: "first", signature: signature).get()

        // …and a downstream repo that fetches from it through the credential-carrying overload.
        // On a file remote the credential callback is simply never invoked; what this pins down
        // is that fetch now goes through callback-wired options at all (it used to build default
        // options that dropped the credentials on the floor).
        let downstreamDir = try makeTempDir("downstream")
        let downstream = try Repository.create(at: downstreamDir).get()
        let remote = try downstream.addRemote(named: "origin", url: upstreamDir.path).get()
        try downstream.fetch(remote, credentials: .default).get()

        // The default refspec maps the upstream default branch (name varies with host config)
        // into refs/remotes/origin/*.
        let fetched = try downstream.remoteBranches().get()
        #expect(!fetched.isEmpty)
    }

    // MARK: Typed error helpers

    @Test("a missing remote surfaces as isLibGit2NotFound, not string matching")
    func notFoundIsTyped() throws {
        let dir = try makeTempDir("notfound")
        let repo = try Repository.create(at: dir).get()
        guard case .failure(let error) = repo.remote(named: "nope") else {
            Issue.record("expected a failure looking up a nonexistent remote")
            return
        }
        #expect(error.isLibGit2NotFound)
        #expect(!error.isLibGit2AuthenticationFailure)
    }
}
