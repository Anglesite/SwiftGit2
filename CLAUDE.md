# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

## What this repository is

Anglesite's fork of [mbernson/SwiftGit2](https://github.com/mbernson/SwiftGit2) (itself a fork
of the original [SwiftGit2/SwiftGit2](https://github.com/SwiftGit2/SwiftGit2)): Swift bindings
to libgit2, with libgit2 compiled from source as part of the package (the `Clibgit2` target
builds the `libgit2/` git submodule directly — no system libgit2, no prebuilt binaries).

Its sole consumer is [Anglesite-app](https://github.com/Anglesite/Anglesite-app), a sandboxed
Mac App Store app. Under the App Sandbox, `/usr/bin/git` cannot execute at all
(Anglesite-app#640), so the app performs every git operation **in-process** through this
library: site scaffolding commits, content add/remove commits, backup (`add -A` → commit →
push over HTTPS), and publish-to-GitHub preflight. Robustness expectations follow from that:
a crash here is a crash of the whole app, and repositories being operated on are
**user-owned directories** whose `.git/config` may have been hand-edited.

## Branch layout (important — three lineages coexist)

| Branch | What it is |
|---|---|
| `anglesite/main` | **The integration branch.** mbernson's SPM lineage plus Anglesite's patches. This is what Anglesite-app pins. Base new work here. |
| `develop` | GitHub default branch; tracks mbernson upstream without the Anglesite patches. |
| `master`, `main` | Legacy upstream lineages (Carthage/Xcode-project era, pre-SPM). Do not base work on these. |

Anglesite-app pins this package **by commit revision** (not tag/branch) in its `Package.swift`
— see the `.package(url: "https://github.com/Anglesite/SwiftGit2.git", revision: "…")` entry
there. Two consequences:

1. Landing a change here does nothing for the app until the app's pin is bumped in a separate
   Anglesite-app PR. Bump deliberately, never to a moving branch.
2. The revision pin is also load-bearing for SwiftPM: the `Clibgit2` target uses
   `cSettings: .unsafeFlags`, which SwiftPM forbids in dependencies resolved by *version*
   requirement. A tagged release of this package would be unusable by the app unless the
   unsafe flags are removed first.

## Building and testing

```sh
git submodule update --init          # libgit2 sources (currently v1.9.x) — required
swift build
swift test                           # Swift Testing (@Suite/@Test), not XCTest/Quick
```

- macOS/iOS-family platforms only (see `Package.swift`); the app consumes it Darwin-only.
  There is no Linux support — libgit2 is compiled with Darwin-specific defines
  (SecureTransport, CommonCrypto).
- Test suites that touch shared libgit2 state run `.serialized` — keep that on new suites;
  uncoordinated concurrent libgit2 use is unsafe.
- CI (`.github/workflows/`) runs on pull requests. Open a PR to get a run; pushes to
  `anglesite/main` alone do not trigger it (the `push:` trigger lists only `master`).

## API surface Anglesite-app depends on (do not break)

From `Sources/AnglesiteCore` in Anglesite-app (`SwiftGit2Bootstrap`, `InProcessGit`,
`RepoBootstrap`, `GitInitRunner`, `NativeContentOperations`, `InboxSubmissionCommitter`):

- `SwiftGit2Init()` — must be called before any other API; the app funnels this through a
  `static let` (`SwiftGit2Bootstrap.ensureInitialized`).
- `Repository.at(_:)`, `Repository.create(at:bare:)`
- `Repository.HEAD()`, `remote(named:)`, `remoteBranch(named:)`, `status(options:)`,
  `aheadBehind(local:upstream:)`
- `Repository.add(path:)`, `addAll()`, `remove(path:)`, `headHasEntry(atPath:)`,
  `restorePathFromHEAD(_:)`
- `Repository.defaultSignature()`, `commit(message:signature:)` (must keep working on an
  unborn HEAD — that's the fork's founding patch, see below)
- `Repository.push(remoteName:refspec:credentials:)`, `addRemote(named:url:)`
- `Credentials.plaintext` (HTTPS token auth) and `.default`
- `Diff.Status`, `StatusEntry`, `Branch`, `Signature`, `OID`

Auth in the app is HTTPS-only (`x-access-token` + GitHub PAT). SSH is effectively unavailable
in its sandbox anyway: libgit2 is built with `GIT_SSH_EXEC` (shells out to `ssh`), and the App
Sandbox blocks that exec just like it blocks `git`.

## Fork conventions

- **Founding patch:** `commit(message:signature:)` creates a parentless first commit on an
  unborn HEAD instead of failing (upstream SwiftGit2/SwiftGit2#174). It keys off
  `GIT_ENOTFOUND` specifically — any other error still propagates. Preserve that exactness.
- Fork additions carry a doc-comment line `Added for anglesite/SwiftGit2 (Anglesite-app#NNN)`.
  Follow it for new API so the diff against upstream stays auditable.
- **Before adding anything new**, check for an existing upstream PR (SwiftGit2/SwiftGit2,
  mbernson/SwiftGit2, or open here) and pull it in rather than re-implementing — the fork's
  policy is to keep its diff small and mergeable back (see README).
- API style is upstream's: `Result<T, NSError>` returns (no `throws`), value types everywhere
  except the `Repository` class, tabs for indentation in the inherited files.
- Fork tests live in `Tests/SwiftGit2Tests/Anglesite*Spec.swift`; new fork behavior gets
  covered there, in Swift Testing style.

## Sharp edges to keep in mind

- Nothing enforces `SwiftGit2Init()` — calling any API first fails at runtime with a libgit2
  "library has not been initialized" class of error, not a compile error.
- `Repository` is not thread-safe and not `Sendable`. The app's pattern (open a fresh
  `Repository` per operation, run blocking calls off the cooperative pool) is the supported
  one.
- Several inherited call sites let pointers from `withUnsafeMutablePointer` /
  `NSString.utf8String` escape their guaranteed lifetimes (e.g. the `git_strarray`
  construction in `add(path:)`/`push`/`restorePathFromHEAD`). It works today; don't copy the
  pattern into new code — keep the C call inside the pointer's scope.
- `NSError(gitError:)` reads `giterr_last()`, which is thread-local — build the error on the
  same thread that made the failing libgit2 call.
