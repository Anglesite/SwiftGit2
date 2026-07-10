# SwiftGit2

> [!NOTE]
> **This is [Anglesite](https://github.com/Anglesite/Anglesite-app)'s fork of
> [mbernson/SwiftGit2](https://github.com/mbernson/SwiftGit2)**, itself a fork of the original
> [SwiftGit2/SwiftGit2](https://github.com/SwiftGit2/SwiftGit2). It exists to carry one patch:
> `Repository.commit(message:signature:)` now handles the first commit on a freshly-`git init`'d
> (unborn HEAD) repository, instead of failing with `reference 'refs/heads/master' not found`.
> See [SwiftGit2/SwiftGit2#174](https://github.com/SwiftGit2/SwiftGit2/issues/174) (open since
> 2020) for the upstream bug report and the `stevengharris` comment this fix's shape follows, and
> [Anglesite-app#640](https://github.com/Anglesite/Anglesite-app/issues/640) for why Anglesite
> needs it (a Swift-native, in-process git library instead of shelling out to `/usr/bin/git`,
> which App Sandbox blocks entirely).
>
> **Before making further direct modifications to this fork**, check whether an existing PR
> (upstream at `SwiftGit2/SwiftGit2`, on `mbernson/SwiftGit2`, or already open here) already
> covers the change — pull that in instead of re-implementing it, to keep this fork's diff
> against upstream as small and mergeable-back as possible. As of 2026-07-10, neither upstream
> nor `mbernson/SwiftGit2` has any open PR addressing #174 — only the issue-comment-level
> proposal this fix follows — so the patch here is original, not a duplicate of in-flight work.
> Re-check before adding anything new.

> [!WARNING]
> The SwiftGit2 maintainers are in the process of migrating SwiftGit2 to the Swift Package Manager.
> 
> This causes the following breaking changes:
>
> * The Carthage configuration and Xcode project are gone and are longer supported.
> * SwiftGit2 must now be explicitly initialized by the application by calling `SwiftGit2Init()`. Its resources may be cleaned up again using `SwiftGit2Shutdown()`.
> * The dependency libssh2 is not yet integrated. The impact is that SwiftGit2 on iOS cannot interact with remote repositories over SSH. (Remotes that use HTTPS are supported using the HTTP client that ships with libgit2.)

[![Build Status](https://github.com/SwiftGit2/SwiftGit2/actions/workflows/BuildPR.yml/badge.svg)](https://github.com/SwiftGit2/SwiftGit2/actions)
[![GitHub release](https://img.shields.io/github/release/SwiftGit2/SwiftGit2.svg)](https://github.com/SwiftGit2/SwiftGit2/releases)
![Swift 5.9.x](https://img.shields.io/badge/Swift-5.9.x-orange.svg)

Swift bindings to [libgit2](https://github.com/libgit2/libgit2).

```swift
let URL: URL = ...
let result = Repository.at(URL)
switch result {
case let .success(repo):
    let latestCommit = repo
        .HEAD()
        .flatMap {
            repo.commit($0.oid)
        }

    switch latestCommit {
    case let .success(commit):
        print("Latest Commit: \(commit.message) by \(commit.author.name)")

    case let .failure(error):
        print("Could not get commit: \(error)")
    }

case let .failure(error):
    print("Could not open repository: \(error)")
}
```

## Design

SwiftGit2 uses value types wherever possible. That means using Swift’s `struct`s and `enum`s without holding references to libgit2 objects. This has a number of advantages:

1. Values can be used concurrently.
2. Consuming values won’t result in disk access.
3. Disk access can be contained to a smaller number of APIs.

This vastly simplifies the design of long-lived applications, which are the most common use case with Swift. Consequently, SwiftGit2 APIs don’t necessarily map 1-to-1 with libgit2 APIs.

All methods for reading from or writing to a repository are on SwiftGit’s only `class`: `Repository`. This highlights the failability and mutation of these methods, while freeing up all other instances to be immutable `struct`s and `enum`s.

## Adding SwiftGit2 to your Project

You can add SwiftGit2 to your project using the [Swift Package Manager](https://www.swift.org/documentation/package-manager/).

In Xcode, go to your project settings, then to `Package Dependencies`. Add SwiftGit2 using the URL:

```
https://github.com/SwiftGit2/SwiftGit2.git
```

If you're developing an SPM-based project, open your `Package.swift` file and add SwiftGit2 as a dependency:

```swift
.package(url: "https://github.com/SwiftGit2/SwiftGit2.git", from: "1.0.0")
```

And don't forget to reference it from your target:

```swift
.target(name: "YourProject", dependencies: ["SwiftGit2"]),
```

## Developing SwiftGit2

If you want to build and test SwiftGit2 locally for development purposes:

1. Clone SwiftGit2
2. Run `git submodule update --init` to clone the libgit2 submodule
3. Run `swift test` or open the `Package.swift` file to develop and test using Xcode

## Contributions

We :heart: to receive pull requests! GitHub makes it easy:

1. Fork the repository
2. Create a branch with your changes
3. Send a Pull Request

All contributions should match GitHub’s [Swift Style Guide](https://github.com/github/swift-style-guide).

## License

SwiftGit2 is available under the [MIT license](https://github.com/SwiftGit2/SwiftGit2/blob/master/LICENSE.md).
