//
//  AnglesiteThreadSafetySpec.swift
//  SwiftGit2Tests
//
//  Coverage for the GIT_THREADS build define (Anglesite-app#994).
//
//  This package compiles libgit2 with LIBGIT2_NO_FEATURES_H, so nothing about the build is
//  inferred — every feature is exactly what Package.swift's define list says. GIT_THREADS was
//  missing from that list even though libgit2's own CMake build defaults it on, which silently
//  selected the single-threaded build: src/util/thread.c's `#if !defined(GIT_THREADS)` branch
//  backs git_tlsdata_* with a process-wide `static tlsdata_value tlsdata_values[16]` instead of
//  real TLS, and git_mutex_* compile to no-ops.
//
//  libgit2 keeps its error state in that storage ("the error handling in libgit2 is itself
//  handled by thread-local data storage" — thread.h), so two threads calling into libgit2 at
//  once grew one shared git_str and aborted the whole process inside realloc:
//
//      git_error_set -> git_error_vset -> git_str_vprintf -> git_str_grow -> git__realloc
//      -> ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED -> abort
//
//  Deliberately NOT .serialized, unlike every other suite here — concurrency is the thing under
//  test. Note what that means for a regression: this doesn't fail, it takes the whole test
//  process down with SIGABRT and no named test, so a bare "exited with unexpected signal code 6"
//  from swiftpm-testing-helper is the symptom to recognise.
//
//  Repository itself remains non-Sendable and single-threaded; the supported pattern is one
//  fresh Repository per operation, which is what these tests do. GIT_THREADS is about libgit2's
//  *shared* state (errors, mutexes) surviving that pattern being run in parallel.

import Foundation
import Testing
import Clibgit2
import SwiftGit2

@Suite("Anglesite libgit2 thread safety") struct AnglesiteThreadSafetySpec {

    @Test("libgit2 reports the threads feature")
    func reportsThreadsFeature() {
        _ = SwiftGit2Init()

        let features = git_libgit2_features()

        #expect(UInt32(features) & GIT_FEATURE_THREADS.rawValue != 0)
    }

    /// The actual regression reproducer. Verified against this commit: with `GIT_THREADS` removed
    /// from `Package.swift` it takes the test process down 3 runs out of 3; with it, 5 out of 5
    /// clean.
    ///
    /// The formulation matters, and a weaker one gives false confidence — a first attempt using 64
    /// concurrent failing calls with short paths passed happily on the broken build. `git_error_vset`
    /// does `git_str_clear` (which zeroes the length but keeps the allocation) and then vprintf, so
    /// the shared buffer only reallocs when a message is longer than every message before it. Path
    /// lengths must therefore climb monotonically, and climb far enough that reallocation keeps
    /// happening for the whole run rather than converging after a handful of iterations.
    @Test("concurrent failing calls don't corrupt libgit2's shared error buffer")
    func concurrentErrorsDoNotCorruptErrorBuffer() {
        _ = SwiftGit2Init()
        let base = FileManager.default.temporaryDirectory
        let missing = (0..<1024).map { i in
            base.appendingPathComponent("swiftgit2-absent-" + String(repeating: "x", count: i * 64), isDirectory: true)
        }

        DispatchQueue.concurrentPerform(iterations: missing.count) { i in
            if case .success = Repository.at(missing[i]) {
                Issue.record("expected no repository at index \(i)")
            }
        }
    }

    /// Not a reproducer on its own — it passes on the broken build too. It's here because the
    /// error buffer isn't the only shared state `GIT_THREADS` governs (`git_mutex_*` are no-ops
    /// without it), so this asserts that real work run in parallel produces *correct* results and
    /// not merely a process that survived.
    @Test("concurrent real repository work completes without corrupting shared state")
    func concurrentRepositoryWorkSucceeds() throws {
        _ = SwiftGit2Init()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgit2-threads-spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let count = 16
        let dirs = try (0..<count).map { i -> URL in
            let dir = root.appendingPathComponent("repo-\(i)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let signature = Signature(name: "Test", email: "test@example.com")
        let commits = Locked<[Int: OID]>([:])

        // A fresh Repository per iteration — the app's pattern — but sixteen of them at once, so
        // libgit2's process-wide state is exercised from every thread the pool hands out.
        DispatchQueue.concurrentPerform(iterations: count) { i in
            do {
                let repo = try Repository.create(at: dirs[i]).get()
                try "repo \(i)".write(to: dirs[i].appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
                try repo.add(path: "f.txt").get()
                let commit = try repo.commit(message: "commit \(i)", signature: signature).get()
                commits.withValue { $0[i] = commit.oid }
            } catch {
                Issue.record("repo \(i) failed: \(error)")
            }
        }

        let recorded = commits.withValue { $0 }
        #expect(recorded.count == count)
        // Distinct contents must produce distinct OIDs — a shared-state mix-up would collide them.
        #expect(Set(recorded.values).count == count)
    }
}

/// Minimal mutex box; the concurrentPerform bodies need somewhere to collect results.
private final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
