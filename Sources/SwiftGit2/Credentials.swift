//
//  Credentials.swift
//  SwiftGit2
//
//  Created by Tom Booth on 29/02/2016.
//  Copyright © 2016 GitHub, Inc. All rights reserved.
//

import Foundation
import Clibgit2

public enum Credentials {
	case `default`
	case sshAgent
	case plaintext(username: String, password: String)
	case sshMemory(username: String, publicKey: String, privateKey: String, passphrase: String)
}

/// Payload threaded through libgit2's remote callbacks (fetch, clone, and push). A class so the
/// C callbacks can read the credentials — and append per-ref push rejections — through an
/// *unretained* pointer whose lifetime is scoped to the remote operation (`withExtendedLifetime`
/// at each call site). Deliberately NOT a retain-transfer (`takeRetainedValue`): libgit2 may
/// invoke the credential callback any number of times per operation (once per authentication
/// retry), so a retain-transfer over-releases on the second invocation — and leaks when the
/// remote never asks for credentials at all. Added for anglesite/SwiftGit2 (Anglesite-app#653).
internal final class RemoteCallbackPayload {
	let credentials: Credentials

	/// Number of times libgit2 has asked for credentials during this operation. The credentials
	/// above are fixed, so a repeated request means the server rejected them — replying with the
	/// same answer forever would loop until the remote hangs up.
	var credentialAttempts = 0

	/// Per-ref rejection messages collected by `pushUpdateReferenceCallback` (push only).
	var rejections: [String] = []

	/// Fixed credentials can't get righter by retrying; allow a few attempts (some transports
	/// legitimately re-ask, e.g. to negotiate an auth mechanism) and then fail fast.
	static let maxCredentialAttempts = 3

	init(credentials: Credentials) {
		self.credentials = credentials
	}

	/// True once `credentialsCallback` has refused further attempts — used by call sites to map
	/// libgit2's generic `GIT_EUSER` into a specific authentication-failure error.
	var credentialAttemptsExhausted: Bool {
		return credentialAttempts > RemoteCallbackPayload.maxCredentialAttempts
	}

	/// The error reported when the attempt budget runs out. Coded as `GIT_EAUTH` so
	/// `NSError.isLibGit2AuthenticationFailure` recognizes it without string matching.
	func makeAuthenticationError() -> NSError {
		return NSError(
			domain: libGit2ErrorDomain,
			code: Int(GIT_EAUTH.rawValue),
			userInfo: [
				NSLocalizedDescriptionKey: "authentication failed: the server rejected the "
					+ "provided credentials \(RemoteCallbackPayload.maxCredentialAttempts) times.",
				NSLocalizedFailureReasonErrorKey: "credential callback gave up after "
					+ "\(RemoteCallbackPayload.maxCredentialAttempts) attempts.",
			]
		)
	}
}

/// The credential callback for fetch, clone, and push. Reads the payload unretained — see
/// `RemoteCallbackPayload` for the lifetime contract. Returns `GIT_EUSER` once the attempt
/// budget is exhausted so a rejected fixed credential fails fast instead of replaying until the
/// server drops the connection; call sites translate that into `makeAuthenticationError()`.
internal func credentialsCallback(
	cred: UnsafeMutablePointer<UnsafeMutablePointer<git_cred>?>?,
	url: UnsafePointer<CChar>?,
	username: UnsafePointer<CChar>?,
	_: UInt32,
	payload: UnsafeMutableRawPointer? ) -> Int32 {

	guard let payload = payload else { return -1 }
	let holder = Unmanaged<RemoteCallbackPayload>.fromOpaque(payload).takeUnretainedValue()

	holder.credentialAttempts += 1
	guard holder.credentialAttempts <= RemoteCallbackPayload.maxCredentialAttempts else {
		return GIT_EUSER.rawValue
	}

	let result: Int32

	// Find username_from_url
	let name = username.map(String.init(cString:))

	switch holder.credentials {
	case .default:
		result = git_cred_default_new(cred)
	case .sshAgent:
		result = git_cred_ssh_key_from_agent(cred, name!)
	case .plaintext(let username, let password):
		result = git_cred_userpass_plaintext_new(cred, username, password)
	case .sshMemory(let username, let publicKey, let privateKey, let passphrase):
		result = git_cred_ssh_key_memory_new(cred, username, publicKey, privateKey, passphrase)
	}

	return (result != GIT_OK.rawValue) ? -1 : 0
}
