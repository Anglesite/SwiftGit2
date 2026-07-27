//
//  Bundle.swift
//  SwiftGit2
//
//  Reading git bundles. Added for anglesite/SwiftGit2 (Anglesite-app#988).
//
//  libgit2 has no bundle support of any kind — there is no `git_bundle_*` API, and
//  `git_clone` does not recognise a bundle file as a remote (it reports "could not find
//  repository at …/x.bundle" for thin and complete bundles alike). Anglesite-app's container
//  edit-sync hands a bundle back from the guest over stdout and had no way to read it, so the
//  whole path was dead (Anglesite-app#988); Anglesite-app#655 is the same gap in its iCloud
//  sync transport.
//
//  A bundle is not an opaque format: it is a short *plain-text* header followed by an ordinary
//  packfile, and libgit2 handles packfiles well. So this parses the header itself and hands the
//  pack to `git_odb_write_pack`, which resolves thin-pack bases (REF_DELTA against objects the
//  bundle doesn't carry) out of the receiving repository's own object database.

import Foundation
import Clibgit2

/// The plain-text header of a git bundle.
///
/// Added for anglesite/SwiftGit2 (Anglesite-app#988).
public struct BundleHeader: Equatable {
	/// Objects the bundle assumes the receiving repository already has. A bundle created with a
	/// negative revision (`git bundle create out.bundle some-ref ^parent`) is *thin*: its pack
	/// deltas are expressed against these, and they are not included in it.
	public let prerequisites: [OID]

	/// The bundle's refs, keyed by full ref name (e.g. `refs/heads/main`).
	public let references: [String: OID]

	public init(prerequisites: [OID], references: [String: OID]) {
		self.prerequisites = prerequisites
		self.references = references
	}
}

/// A bundle that could be read as a file but not understood as a bundle. Distinct from
/// `libGit2ErrorDomain` errors, which come from libgit2 itself.
///
/// Added for anglesite/SwiftGit2 (Anglesite-app#988).
public let swiftGit2BundleErrorDomain = "org.anglesite.SwiftGit2.bundle"

public enum BundleError: Int {
	/// Not a git bundle: the signature line is missing or unrecognised.
	case notABundle = 1
	/// A bundle whose version this cannot parse (v3's capability lines are not supported).
	case unsupportedVersion = 2
	/// The header is missing its terminating blank line, or a line is malformed.
	case malformedHeader = 3
	/// The receiving repository is missing objects the bundle's pack deltas are expressed
	/// against, so the pack cannot be applied to it.
	case missingPrerequisites = 4
}

private func bundleError(_ code: BundleError, _ message: String) -> NSError {
	NSError(
		domain: swiftGit2BundleErrorDomain, code: code.rawValue,
		userInfo: [NSLocalizedDescriptionKey: message])
}

public extension Repository {
	/// Reads the git bundle at `url`, writing its packed objects into this repository's object
	/// database, and returns the bundle's header.
	///
	/// The equivalent of `git bundle unbundle` minus ref creation: objects land in the ODB and
	/// the caller decides what, if anything, to point at them. Nothing here writes a ref or
	/// touches the working tree or index.
	///
	/// A *thin* bundle applies only to a repository that already has its prerequisites — those
	/// are checked up front, so a repository that has diverged fails with a clear
	/// `missingPrerequisites` error naming what it lacks, rather than the unresolved-delta
	/// failure the packfile layer would otherwise report much later.
	///
	/// Added for anglesite/SwiftGit2 (Anglesite-app#988).
	func unbundle(at url: URL) -> Result<BundleHeader, NSError> {
		let data: Data
		do {
			data = try Data(contentsOf: url, options: .mappedIfSafe)
		} catch {
			return .failure(error as NSError)
		}

		let header: BundleHeader
		let pack: Data
		switch Self.parseBundle(data) {
		case .success(let parsed): (header, pack) = parsed
		case .failure(let error): return .failure(error)
		}

		var odb: OpaquePointer? = nil
		let odbResult = git_repository_odb(&odb, self.pointer)
		guard odbResult == GIT_OK.rawValue, let odb else {
			return .failure(NSError(gitError: odbResult, pointOfFailure: "git_repository_odb"))
		}
		defer { git_odb_free(odb) }

		let missing = header.prerequisites.filter { prerequisite in
			var oid = prerequisite.oid
			return git_odb_exists(odb, &oid) != 1
		}
		guard missing.isEmpty else {
			return .failure(bundleError(
				.missingPrerequisites,
				"bundle requires objects this repository does not have: "
					+ missing.map(\.description).joined(separator: ", ")))
		}

		var writepack: UnsafeMutablePointer<git_odb_writepack>? = nil
		let writepackResult = git_odb_write_pack(&writepack, odb, nil, nil)
		guard writepackResult == GIT_OK.rawValue, let writepack else {
			return .failure(NSError(gitError: writepackResult, pointOfFailure: "git_odb_write_pack"))
		}
		defer { writepack.pointee.free(writepack) }

		var stats = git_indexer_progress()
		let appendResult = pack.withUnsafeBytes { buffer in
			writepack.pointee.append(writepack, buffer.baseAddress, buffer.count, &stats)
		}
		guard appendResult == GIT_OK.rawValue else {
			return .failure(NSError(gitError: appendResult, pointOfFailure: "git_odb_writepack.append"))
		}

		let commitResult = writepack.pointee.commit(writepack, &stats)
		guard commitResult == GIT_OK.rawValue else {
			return .failure(NSError(gitError: commitResult, pointOfFailure: "git_odb_writepack.commit"))
		}

		return .success(header)
	}

	/// Splits a bundle into its header and its packfile.
	///
	/// Format (`Documentation/gitformat-bundle.txt`), confirmed against real `git bundle create`
	/// output: a signature line, then any number of `-<oid> <comment>` prerequisite lines and
	/// `<oid> <refname>` reference lines in either order, then an empty line, then the pack.
	private static func parseBundle(_ data: Data) -> Result<(BundleHeader, Data), NSError> {
		let v2 = Data("# v2 git bundle\n".utf8)
		let v3 = Data("# v3 git bundle\n".utf8)
		guard data.starts(with: v2) else {
			// v3 interposes `@capability[=value]` lines between the signature and the
			// prerequisites, and exists to carry things (object filters, unusual hash
			// algorithms) that change how the pack must be read. Refusing it is honest;
			// parsing past the capabilities and hoping would not be.
			if data.starts(with: v3) {
				return .failure(bundleError(
					.unsupportedVersion, "v3 git bundles are not supported"))
			}
			return .failure(bundleError(.notABundle, "not a git bundle"))
		}

		// The header is ASCII and ends at the first blank line. Everything after it is the pack,
		// which is binary and must not be touched by any text processing.
		guard let terminator = data.range(of: Data("\n\n".utf8), in: v2.count - 1..<data.count) else {
			return .failure(bundleError(
				.malformedHeader, "bundle header has no terminating blank line"))
		}
		let headerBody = data[v2.count..<terminator.lowerBound + 1]
		let pack = data[terminator.upperBound...]

		guard let text = String(data: headerBody, encoding: .utf8) else {
			return .failure(bundleError(.malformedHeader, "bundle header is not valid UTF-8"))
		}

		var prerequisites: [OID] = []
		var references: [String: OID] = [:]
		for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
			if line.hasPrefix("-") {
				// `-<oid> <comment>`; the comment is the tip's subject line and is advisory.
				let body = line.dropFirst()
				let oidText = body.prefix { $0 != " " }
				guard let oid = OID(string: String(oidText)) else {
					return .failure(bundleError(
						.malformedHeader, "unparseable prerequisite object id: \(oidText)"))
				}
				prerequisites.append(oid)
			} else {
				// `<oid> <refname>`. Ref names cannot contain spaces, so a single split is safe.
				guard let separator = line.firstIndex(of: " ") else {
					return .failure(bundleError(
						.malformedHeader, "bundle reference line has no ref name: \(line)"))
				}
				guard let oid = OID(string: String(line[line.startIndex..<separator])) else {
					return .failure(bundleError(
						.malformedHeader, "unparseable reference object id: \(line)"))
				}
				references[String(line[line.index(after: separator)...])] = oid
			}
		}

		return .success((BundleHeader(prerequisites: prerequisites, references: references), Data(pack)))
	}
}
