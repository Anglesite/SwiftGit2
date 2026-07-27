// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftGit2",
    platforms: [
        .macOS(.v10_13),
        .iOS("15.5"),
        .tvOS(.v13),
        .visionOS(.v1),
        .macCatalyst(.v15),
    ],
    products: [
        .library(
            name: "SwiftGit2",
            targets: ["SwiftGit2"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ZipArchive/ZipArchive.git", from: "2.5.5"),
    ],
    targets: [
        .target(
            name: "SwiftGit2",
            dependencies: ["Clibgit2"]
        ),
        .testTarget(
            name: "SwiftGit2Tests",
            dependencies: ["SwiftGit2", "Clibgit2", "ZipArchive"],
            resources: [.copy("Fixtures")]
        ),
        .target(
            name: "Clibgit2",
            path: "libgit2",
            exclude: [
                "deps/llhttp/CMakeLists.txt",
                "deps/llhttp/LICENSE-MIT",
                "deps/pcre/CMakeLists.txt",
                "deps/pcre/COPYING",
                "deps/pcre/LICENCE",
                "deps/pcre/cmake",
                "deps/pcre/config.h.in",
                "deps/xdiff/CMakeLists.txt",
                "deps/zlib/CMakeLists.txt",
                "deps/zlib/LICENSE",
                "src/libgit2/CMakeLists.txt",
                "src/libgit2/config.cmake.in",
                "src/libgit2/experimental.h.in",
                "src/libgit2/git2.rc",
                "src/util/CMakeLists.txt",
                "src/util/git2_features.h.in",
                "src/util/hash/builtin.c",
                "src/util/hash/builtin.h",
                "src/util/hash/collisiondetect.c",
                "src/util/hash/collisiondetect.h",
                "src/util/hash/openssl.c",
                "src/util/hash/openssl.h",
                "src/util/hash/win32.c",
                "src/util/hash/win32.h",
                "src/util/win32",
            ],
            sources: [
                "deps/llhttp",
                "deps/pcre",
                "deps/xdiff",
                "deps/zlib",
                "src/libgit2",
                "src/util",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags([
                  // Disable -fmodules flag. Clang finds (`struct entry`) in a different file (`search.h`).
                  "-fno-modules",
                  // Disable warning: "implicit conversion loses integer precision"
                  "-Wno-single-bit-bitfield-constant-conversion", "-Wno-conversion",
                  // Disable warning: "a function definition without a prototype is deprecated"
                  "-Wno-deprecated-non-prototype",
                ]),

                .headerSearchPath("deps/llhttp"),
                .headerSearchPath("deps/pcre"),
                .headerSearchPath("deps/xdiff"),
                .headerSearchPath("deps/zlib"),
                .headerSearchPath("src/libgit2"),
                .headerSearchPath("src/util"),

                .define("LIBGIT2_NO_FEATURES_H"),
                .define("GIT_ARCH_64", to: "1"),
                .define("GIT_QSORT_BSD", to: "1"),
                .define("GIT_IO_POLL", to: "1"),

                // Thread safety. libgit2's CMake build defaults this on (USE_THREADS=ON, which
                // sets GIT_THREADS 1 and links pthreads — already in libSystem on Darwin), but
                // LIBGIT2_NO_FEATURES_H means nothing here is inferred: every feature is whatever
                // this list says. Without it, src/util/thread.c compiles its `#if
                // !defined(GIT_THREADS)` branch, where git_tlsdata_* is backed by a *process-wide*
                // `static tlsdata_value tlsdata_values[16]` rather than real TLS, and git_mutex_*
                // become no-ops. libgit2 keeps its error state in that storage, so two concurrent
                // calls grow one shared git_str and abort the process in realloc
                // (Anglesite-app#994).
                .define("GIT_THREADS", to: "1"),

                // Git regex configuration
                .define("GIT_REGEX_BUILTIN", to: "1"),
                .define("PCRE_LINK_SIZE", to: "2"),
                .define("SUPPORT_PCRE8", to: "1"),
                .define("LINK_SIZE", to: "2"),
                .define("PARENS_NEST_LIMIT", to: "250"),
                .define("MATCH_LIMIT", to: "10000000"),
                .define("MATCH_LIMIT_RECURSION", to: "10000000"),
                .define("NEWLINE", to: "10"), // LF
                .define("NO_RECURSE", to: "1"),
                .define("POSIX_MALLOC_THRESHOLD", to: "10"),
                .define("BSR_ANYCRLF", to: "0"),
                .define("MAX_NAME_SIZE", to: "32"),
                .define("MAX_NAME_COUNT", to: "10000"),

                // Git SSH transport configuration
                .define("GIT_SSH", to: "1"),
                .define("GIT_SSH_EXEC", to: "1"),

                // Git HTTPS transport configuration
                .define("GIT_HTTPS", to: "1"),
                .define("GIT_HTTPPARSER_BUILTIN", to: "1"),
                .define("GIT_SECURE_TRANSPORT", to: "1"),

                // Git cryptography configuration
                .define("GIT_SHA1_COMMON_CRYPTO", to: "1"),
                .define("GIT_SHA256_COMMON_CRYPTO", to: "1"),
            ]
        ),
    ]
)
