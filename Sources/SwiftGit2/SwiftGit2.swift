//
//  SwiftGit2.swift
//
//
//  Created by Mathijs Bernson on 01/03/2024.
//

import Foundation
import Clibgit2

/// One-time, process-wide libgit2 initialization. Every `Repository` entry point
/// (`at`/`create`/`clone`/`isValid`) touches this before calling into libgit2, so consumers no
/// longer have to remember to call `SwiftGit2Init()` themselves — a forgotten init previously
/// surfaced as a confusing runtime failure on first use. A `static let` initializer runs exactly
/// once, thread-safely, on first access. Explicit `SwiftGit2Init()` calls remain supported
/// (libgit2 reference-counts init/shutdown) — but a `SwiftGit2Shutdown()` that drops the count
/// to zero de-initializes the library out from under this bootstrap, so only pair it with your
/// own explicit init. Added for anglesite/SwiftGit2 (Anglesite-app#653).
internal enum LibGit2Bootstrap {
	static let ensureInitialized: Void = {
		_ = SwiftGit2Init()
	}()
}

public func SwiftGit2Init() -> Result<Int, NSError> {
    let status = git_libgit2_init()
    if status < 0 {
        return .failure(NSError(gitError: status, pointOfFailure: "git_libgit2_init"))
    } else {
        return .success(Int(status))
    }
}

public func SwiftGit2Shutdown() -> Result<Int, NSError> {
    let status = git_libgit2_shutdown()
    if status < 0 {
        return .failure(NSError(gitError: status, pointOfFailure: "git_libgit2_shutdown"))
    } else {
        return .success(Int(status))
    }
}

public func Libgit2Version() -> String {
    var major: Int32 = 0
    var minor: Int32 = 0
    var patch: Int32 = 0
    git_libgit2_version(&major, &minor, &patch)

    let version: String = [major, minor, patch]
        .map(String.init)
        .joined(separator: ".")

    return version
}
