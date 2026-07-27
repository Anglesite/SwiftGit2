//
//  AnglesiteBundleSpec.swift
//  SwiftGit2Tests
//
//  Coverage for `Repository.unbundle(at:)` (Anglesite-app#988).
//
//  Every bundle here is produced by real `/usr/bin/git bundle create` rather than hand-built
//  bytes: the point of the feature is interoperating with git's own output, so a fixture we
//  wrote ourselves would only prove we can read our own writing.
//
//  .serialized: shares the `git` subprocess helper and builds repos on disk; matches the other
//  Anglesite specs. (libgit2's own shared state is thread-safe since GIT_THREADS, see
//  AnglesiteThreadSafetySpec.)

import Foundation
import Testing
import Clibgit2
import SwiftGit2

@Suite("Anglesite bundle reading", .serialized) struct AnglesiteBundleSpec {

	@Test("unbundles a thin bundle into a repository that has its prerequisite")
	func unbundleThin() throws {
		// The shape Anglesite-app's container edit sync actually produces: one commit, exported
		// against its parent, replayed onto a repo sitting at that parent.
		let origin = try GitFixture.make()
		try origin.commit(file: "f.txt", contents: "one", message: "first")
		let host = try origin.clone()
		try origin.commit(file: "f.txt", contents: "two", message: "second")
		let tip = try origin.head()
		let parent = try origin.git(["rev-parse", "HEAD^"])
		try origin.git(["update-ref", "refs/heads/anglesite-persist", tip])
		let bundle = try origin.bundle(["refs/heads/anglesite-persist", "^\(parent)"])

		let repo = try Repository.at(host.directory).get()
		let header = try repo.unbundle(at: bundle).get()

		#expect(header.references == ["refs/heads/anglesite-persist": OID(string: tip)!])
		#expect(header.prerequisites == [OID(string: parent)!])
		// The objects really landed: the commit, its tree, and the edited blob all resolve in a
		// repository that had none of them a moment ago.
		let commit = try repo.commit(OID(string: tip)!).get()
		#expect(commit.message.trimmingCharacters(in: .whitespacesAndNewlines) == "second")
		let tree = try repo.object(from: commit.tree).get() as! Tree
		let entry = try #require(tree.entries["f.txt"])
		let blob = try repo.object(from: entry.object).get() as! Blob
		#expect(String(data: blob.data, encoding: .utf8) == "two")
	}

	@Test("unbundles a complete bundle into an empty repository")
	func unbundleComplete() throws {
		// No prerequisites, so nothing has to pre-exist — the other end of the range from the
		// thin case, and the shape a from-scratch restore (Anglesite-app#655) would use.
		let origin = try GitFixture.make()
		try origin.commit(file: "f.txt", contents: "one", message: "first")
		let tip = try origin.head()
		let bundle = try origin.bundle(["--all"])
		let empty = try GitFixture.makeEmpty()

		let repo = try Repository.at(empty.directory).get()
		let header = try repo.unbundle(at: bundle).get()

		#expect(header.prerequisites.isEmpty)
		#expect(header.references.values.contains(OID(string: tip)!))
		#expect(try repo.commit(OID(string: tip)!).get().oid.description == tip)
	}

	@Test("refuses a thin bundle when the repository lacks its prerequisites")
	func rejectsMissingPrerequisites() throws {
		// The diverged-host case. Without the up-front check this surfaces from deep in the
		// packfile layer as an unresolved-delta failure, which says nothing useful about why.
		let origin = try GitFixture.make()
		try origin.commit(file: "f.txt", contents: "one", message: "first")
		try origin.commit(file: "f.txt", contents: "two", message: "second")
		let parent = try origin.git(["rev-parse", "HEAD^"])
		try origin.git(["update-ref", "refs/heads/anglesite-persist", try origin.head()])
		let bundle = try origin.bundle(["refs/heads/anglesite-persist", "^\(parent)"])
		let unrelated = try GitFixture.makeEmpty()

		let repo = try Repository.at(unrelated.directory).get()
		let result = repo.unbundle(at: bundle)

		guard case .failure(let error) = result else {
			Issue.record("expected unbundle to fail against a repository missing the prerequisite")
			return
		}
		#expect(error.domain == swiftGit2BundleErrorDomain)
		#expect(error.code == BundleError.missingPrerequisites.rawValue)
		#expect(error.localizedDescription.contains(parent))
	}

	@Test("rejects a file that is not a bundle")
	func rejectsNonBundle() throws {
		let fixture = try GitFixture.makeEmpty()
		let notABundle = fixture.directory.appendingPathComponent("not.bundle")
		try Data("PACK not really".utf8).write(to: notABundle)

		let result = try Repository.at(fixture.directory).get().unbundle(at: notABundle)

		guard case .failure(let error) = result else {
			Issue.record("expected unbundle to reject a non-bundle file")
			return
		}
		#expect(error.code == BundleError.notABundle.rawValue)
	}

	@Test("rejects a v3 bundle rather than misreading its capability lines")
	func rejectsV3() throws {
		// v3 puts `@capability` lines between the signature and the prerequisites, and exists to
		// signal things (object filters, other hash algorithms) that change how the pack must be
		// read. Parsing past them and hoping would corrupt silently; refusing is honest.
		let fixture = try GitFixture.makeEmpty()
		let v3 = fixture.directory.appendingPathComponent("v3.bundle")
		try Data("# v3 git bundle\n@object-format=sha256\n\nPACK".utf8).write(to: v3)

		let result = try Repository.at(fixture.directory).get().unbundle(at: v3)

		guard case .failure(let error) = result else {
			Issue.record("expected unbundle to reject a v3 bundle")
			return
		}
		#expect(error.code == BundleError.unsupportedVersion.rawValue)
	}

	@Test("rejects a header with no terminating blank line")
	func rejectsUnterminatedHeader() throws {
		let fixture = try GitFixture.makeEmpty()
		let truncated = fixture.directory.appendingPathComponent("truncated.bundle")
		try Data("# v2 git bundle\nc110abddc8d8a575d9e41f21747cdfc97a2a0420 refs/heads/x\n".utf8)
			.write(to: truncated)

		let result = try Repository.at(fixture.directory).get().unbundle(at: truncated)

		guard case .failure(let error) = result else {
			Issue.record("expected unbundle to reject a header with no blank line")
			return
		}
		#expect(error.code == BundleError.malformedHeader.rawValue)
	}
}

/// A throwaway git repository driven by `/usr/bin/git`, so the bundles under test are genuinely
/// git's own output.
///
/// A class, not a struct, so `deinit` can remove the directory when the test that made it ends —
/// these tests build up to three repositories each, and `defer`-per-fixture at every call site
/// would be noisier than it is worth.
private final class GitFixture {
	let directory: URL

	private init(directory: URL) { self.directory = directory }

	deinit { try? FileManager.default.removeItem(at: directory) }

	/// Alias for ``makeEmpty()``; both produce an initialised repository with an identity set.
	static func make() throws -> GitFixture { try makeEmpty() }

	static func makeEmpty() throws -> GitFixture {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swiftgit2-bundle-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let fixture = GitFixture(directory: directory)
		try fixture.git(["init"])
		try fixture.git(["config", "user.email", "test@example.com"])
		try fixture.git(["config", "user.name", "Test"])
		return fixture
	}

	/// A clone of this repository, which therefore shares its history — the "host sitting at the
	/// parent commit" side of a thin-bundle exchange.
	func clone() throws -> GitFixture {
		let destination = FileManager.default.temporaryDirectory
			.appendingPathComponent("swiftgit2-bundle-\(UUID().uuidString)", isDirectory: true)
		try git(["clone", directory.path, destination.path])
		return GitFixture(directory: destination)
	}

	func commit(file: String, contents: String, message: String) throws {
		try contents.write(to: directory.appendingPathComponent(file), atomically: true, encoding: .utf8)
		try git(["add", "-A"])
		try git(["commit", "-m", message])
	}

	func head() throws -> String { try git(["rev-parse", "HEAD"]) }

	/// Writes the bundle inside this fixture's own directory so `deinit` sweeps it up too.
	/// `.git/` is what makes the repository, so a stray file beside it is inert.
	func bundle(_ revisions: [String]) throws -> URL {
		let bundle = directory.appendingPathComponent("\(UUID().uuidString).bundle")
		try git(["bundle", "create", bundle.path] + revisions)
		return bundle
	}

	@discardableResult
	func git(_ arguments: [String]) throws -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = arguments
		process.currentDirectoryURL = directory
		let stdout = Pipe()
		process.standardOutput = stdout
		process.standardError = Pipe()
		try process.run()
		let data = stdout.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
