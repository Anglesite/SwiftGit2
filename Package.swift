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
                "deps/pcre2/CMakeLists.txt",
                "deps/pcre2/LICENCE.md",
                "deps/pcre2/config.h.in",
                // Fuzzing harness with its own entry point; libgit2's CMake doesn't build it either.
                "deps/pcre2/pcre2_fuzzsupport.c",
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
                "deps/pcre2",
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
                .headerSearchPath("deps/pcre2"),
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

                // Git regex configuration: the bundled PCRE2 (libgit2 1.9.5+ replaced PCRE with
                // PCRE2). Mirrors libgit2's cmake/SelectRegex.cmake ("builtin") and
                // deps/pcre2/CMakeLists.txt. There is no generated config.h (no HAVE_CONFIG_H), so
                // the static configuration is passed here instead, plus the HAVE_* checks CMake
                // would detect with clang on Darwin (the only ones pcre2 reads).
                .define("GIT_REGEX_BUILTIN", to: "1"),
                .define("PCRE2_CODE_UNIT_WIDTH", to: "8"),
                .define("PCRE2_STATIC"),
                .define("PCRE2_EXPORT", to: ""),
                .define("PCRE2_EXP_DECL", to: ""),
                .define("PCRE2_EXP_DEFN", to: ""),
                .define("SUPPORT_PCRE2_8", to: "1"),
                .define("SUPPORT_UNICODE", to: "1"),
                .define("NEWLINE_DEFAULT", to: "2"), // LF
                .define("LINK_SIZE", to: "2"),
                .define("MAX_VARLOOKBEHIND", to: "255"),
                .define("PARENS_NEST_LIMIT", to: "250"),
                .define("HEAP_LIMIT", to: "20000000"),
                .define("MATCH_LIMIT", to: "10000000"),
                .define("MATCH_LIMIT_DEPTH", to: "MATCH_LIMIT"),
                .define("MAX_NAME_SIZE", to: "128"),
                .define("MAX_NAME_COUNT", to: "10000"),
                .define("HAVE_ASSERT_H", to: "1"),
                .define("HAVE_BUILTIN_MUL_OVERFLOW", to: "1"),
                .define("HAVE_BUILTIN_UNREACHABLE", to: "1"),
                .define("HAVE_ATTRIBUTE_UNINITIALIZED", to: "1"),

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
