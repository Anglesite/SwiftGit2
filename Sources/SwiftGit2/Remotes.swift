//
//  Remotes.swift
//  SwiftGit2
//
//  Created by Matt Diephouse on 1/2/15.
//  Copyright (c) 2015 GitHub, Inc. All rights reserved.
//

import Clibgit2

/// A remote in a git repository.
public struct Remote: Hashable {
	/// The name of the remote.
	public let name: String

	/// The URL of the remote.
	///
	/// This may be an SSH URL, which isn't representable using `NSURL`.
	public let URL: String

	/// Create an instance with a libgit2 `git_remote`.
	///
	/// Fails (returns nil) when the underlying remote has no name (an in-memory/anonymous
	/// remote) or no fetch URL — e.g. a hand-edited `.git/config` whose `[remote "…"]` section
	/// only sets `pushurl`. The previous force-unwraps turned that user-editable state into a
	/// crash of the calling process. Changed for anglesite/SwiftGit2 (Anglesite-app#653).
	public init?(_ pointer: OpaquePointer) {
		guard let name = git_remote_name(pointer).flatMap({ String(validatingUTF8: $0) }),
		      let url = git_remote_url(pointer).flatMap({ String(validatingUTF8: $0) }) else {
			return nil
		}
		self.name = name
		self.URL = url
	}
}
