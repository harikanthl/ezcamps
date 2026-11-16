// swift-tools-version: 6.2
import PackageDescription

// ── THIS PACKAGE IS PART OF THE LINUX BUILD, WHICH NOBODY INTENDED ──────────────────────────────
// (2026-09-11, docs/LINUX_WORKSTATION.md L0.)
//
// `OperatorCore` took an edge to this package on 2026-09-04 (31e6784) for the LLM VOCABULARY only —
// its manifest says so, and it is true: OperatorCore references exactly `LLMToolSpec`, `LLMMessage`,
// `LLMProviderPreset` and `LLMToolCall`, and never a client. But an edge is an edge, so from that
// day every Linux consumer of OperatorCore — the supervisor image included — had to compile this
// package too, and could not.
//
// The vocabulary compiles anywhere. Three HTTP clients do not, and the reason is NOT an import:
//
//     URLSession.bytes(for:)  — the async byte-stream API every one of them uses for SSE —
//     DOES NOT EXIST in swift-corelibs-foundation.
//
// That is an API gap, not a missing module, so there is no guard that makes it compile. They leave
// the Linux build instead, and what leaves with them is stated plainly rather than discovered later:
//
//   ‼️ A LINUX BOX CANNOT TALK TO A MODEL PROVIDER DIRECTLY UNTIL THIS IS ANSWERED. Bots whose work
//   is a conversation run through a worker's own agent (which brings its own HTTP stack inside a
//   container) and not through this package. The day `operator-agentd` wants to hold a model key and
//   call a provider itself (LINUX_WORKSTATION §2.2 says it may), one of these has to happen first:
//   a delegate-based streaming client for Linux behind `LLMClient`, or an async-http-client
//   dependency — and both are a DECISION, not a port. Recorded as LINUX_WORKSTATION §9.6.
//
// `OnDeviceLLM` / `OnDeviceTools` need no help: their `FoundationModels` import is already behind
// `#if canImport`, and Apple Intelligence on a Linux box was never a thing to miss.
#if os(Linux)
let appleOnlySources = [
    "OpenAICompatibleClient.swift",
    "AnthropicMessagesClient.swift",
    "LLMModelCatalog.swift",
]
#else
let appleOnlySources: [String] = []
#endif

let package = Package(
    name: "OperatorLLM",
    // No watchOS: the watch never runs an LLM, and keeping it off keeps
    // FoundationModels linking simple. (Apple deployment minimums only; Linux is unconstrained.)
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "OperatorLLM", targets: ["OperatorLLM"])],
    // No external dependencies — only system frameworks (FoundationModels, Security).
    dependencies: [],
    targets: [
        .target(
            name: "OperatorLLM",
            exclude: appleOnlySources,
            swiftSettings: [.defaultIsolation(nil)]
        ),
        .testTarget(name: "OperatorLLMTests", dependencies: ["OperatorLLM"]),
    ]
)
