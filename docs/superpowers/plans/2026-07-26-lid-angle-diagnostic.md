# MacBook Lid Angle Diagnostic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a read-only Swift command-line diagnostic that safely discovers likely MacBook lid-angle HID devices, watches raw reports, decodes supported angle payloads, and compares them with `AppleClamshellState`.

**Architecture:** A Swift Package executable owns CLI orchestration while hardware access is isolated behind small protocols. Pure parsers, candidate ranking, report decoding, and formatting are unit tested without hardware; IOHID and IORegistry adapters are exercised through bounded on-device validation.

**Tech Stack:** Swift 6.x, Swift Package Manager, Foundation, IOKit, IOHIDManager, XCTest, POSIX signals, shell scripting.

## Global Constraints

- Target hardware: Apple Silicon MacBook Pro, validated first on the user's M1 Pro machine.
- Minimum deployment target: macOS 13.0.
- Toolchain: Swift 6.x through the system Xcode Command Line Tools.
- Package type: Swift Package Manager executable with no third-party runtime dependency.
- Initial release version: `0.1.0`, declared once in package source and reused by CLI output.
- Phase 1 is read-only: no sleep calls, power-setting changes, NVRAM changes, persistence, privilege escalation, HID writes, DriverKit, kernel extensions, or SIP changes.
- Keyboard, keypad, mouse, pointer, trackpad, digitizer, and consumer-control devices must be excluded before ranking.
- A low-confidence candidate must never be opened automatically.
- Hardware conclusions require evidence from at least three physical lid positions plus contemporaneous `AppleClamshellState` values.

---

## Planned File Map

```text
Package.swift
README.md
Sources/LidMonitor/
├── CLI.swift                    # Argument parsing and usage errors
├── ClamshellStateReader.swift   # Read-only IORegistry adapter
├── DiagnosticModels.swift       # Shared immutable domain values
├── HIDDeviceDescriptor.swift    # IOHID metadata normalization
├── HIDReportStream.swift        # Read-only report callback lifecycle
├── LidAngleDecoder.swift        # Pure report-shape decoders
├── LidSensorDiscovery.swift     # Enumeration, exclusion, scoring
├── OutputFormatter.swift        # Deterministic user-visible text
├── RuntimeEnvironment.swift     # Version, architecture, OS metadata
└── main.swift                   # Composition root and signal handling
Tests/LidMonitorTests/
├── CandidateRankingTests.swift
├── CLIParserTests.swift
├── LidAngleDecoderTests.swift
└── OutputFormatterTests.swift
scripts/run-diagnostic.sh
```

## Task Governance Contract

For every implementation task below:

```text
Implement Task N
→ run the task-specific tests
→ review Task N against its Interfaces and Global Constraints
→ fix every finding
→ rerun tests and review
→ require Open P0/P1 = 0
→ commit Task N
```

After all tasks:

```text
Run full package validation
→ perform whole-phase implementation review
→ fix findings
→ rerun full validation
→ require Open P0/P1 = 0
→ perform bounded hardware validation
→ document the observed diagnostic result
```

---

### Task 1: Package Foundation, Domain Models, and CLI Contract

**Files:**
- Create: `Package.swift`
- Create: `Sources/LidMonitor/DiagnosticModels.swift`
- Create: `Sources/LidMonitor/RuntimeEnvironment.swift`
- Create: `Sources/LidMonitor/CLI.swift`
- Create: `Sources/LidMonitor/main.swift`
- Create: `Tests/LidMonitorTests/CLIParserTests.swift`

**Interfaces:**
- Produces: `enum DiagnosticMode { case list; case watch }`
- Produces: `struct CLIOptions: Equatable { let mode: DiagnosticMode; let includeRaw: Bool; let duration: TimeInterval? }`
- Produces: `enum CLIParseError: Error, Equatable`
- Produces: `enum ExitCode: Int32 { case success = 0; case usage = 64; case unavailable = 69; case internalError = 70; case ioFailure = 74 }`
- Produces: `enum AppVersion { static let current = "0.1.0" }`
- Consumes: no earlier task interfaces.

- [ ] **Step 1: Create the Swift package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macbook-lid-monitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macbook-lid-monitor", targets: ["LidMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "LidMonitor",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "LidMonitorTests",
            dependencies: ["LidMonitor"]
        )
    ]
)
```

- [ ] **Step 2: Write failing CLI parser tests**

Create `Tests/LidMonitorTests/CLIParserTests.swift` with tests covering:

```swift
import XCTest
@testable import LidMonitor

final class CLIParserTests: XCTestCase {
    func testNoArgumentsDefaultsToWatch() throws {
        XCTAssertEqual(try CLIParser.parse([]), CLIOptions(mode: .watch, includeRaw: false, duration: nil))
    }

    func testListModeRejectsRaw() {
        XCTAssertThrowsError(try CLIParser.parse(["--list", "--raw"])) { error in
            XCTAssertEqual(error as? CLIParseError, .rawRequiresWatch)
        }
    }

    func testConflictingModesAreRejected() {
        XCTAssertThrowsError(try CLIParser.parse(["--list", "--watch"])) { error in
            XCTAssertEqual(error as? CLIParseError, .conflictingModes)
        }
    }

    func testDurationMustBePositiveFiniteNumber() {
        for value in ["0", "-1", "nan", "inf"] {
            XCTAssertThrowsError(try CLIParser.parse(["--duration", value]))
        }
    }

    func testUnknownOptionIsRejected() {
        XCTAssertThrowsError(try CLIParser.parse(["--unknown"])) { error in
            XCTAssertEqual(error as? CLIParseError, .unknownOption("--unknown"))
        }
    }
}
```

- [ ] **Step 3: Run the targeted tests and verify RED**

Run:

```bash
swift test --filter CLIParserTests
```

Expected: compilation fails because the CLI types do not exist.

- [ ] **Step 4: Implement the domain and CLI types minimally**

Implement `DiagnosticMode`, `CLIOptions`, `CLIParseError`, `ExitCode`, `AppVersion`, and `CLIParser.parse(_:)`. The parser must consume arguments without reading process-global state so it remains unit testable.

Use this exact parser entry point:

```swift
enum CLIParser {
    static func parse(_ arguments: [String]) throws -> CLIOptions
}
```

Implement `RuntimeEnvironment.current()` with:

```swift
struct RuntimeEnvironment: Equatable {
    let appVersion: String
    let architecture: String
    let operatingSystemVersion: String

    static func current() -> RuntimeEnvironment
}
```

Keep `main.swift` limited to parsing and printing a temporary mode line; do not add hardware access yet.

- [ ] **Step 5: Run Task 1 tests and build**

Run:

```bash
swift test --filter CLIParserTests
swift build
swift run macbook-lid-monitor --list
```

Expected:

- CLI parser tests pass.
- Build exits `0`.
- Temporary executable output identifies list mode without touching HID devices.

- [ ] **Step 6: Review Task 1**

Review requirements:

- Version exists in one source location only.
- Parser enforces all mode and duration rules.
- Invalid usage can map to exit code `64`.
- No hardware access, sleep behavior, persistence, or privilege request exists.
- `main.swift` remains a composition root rather than accumulating domain logic.

- [ ] **Step 7: Commit Task 1**

```bash
git add Package.swift Sources Tests
git commit -m "feat: 建立診斷工具 CLI 基礎"
```

---

### Task 2: Safe HID Descriptor Normalization and Candidate Ranking

**Files:**
- Create: `Sources/LidMonitor/HIDDeviceDescriptor.swift`
- Create: `Sources/LidMonitor/LidSensorDiscovery.swift`
- Create: `Tests/LidMonitorTests/CandidateRankingTests.swift`
- Modify: `Sources/LidMonitor/DiagnosticModels.swift`

**Interfaces:**
- Consumes: `ExitCode` from Task 1 for later orchestration only.
- Produces: `struct HIDDeviceDescriptor: Equatable, Sendable`
- Produces: `enum HIDInputClass: Equatable { case keyboard, keypad, mouse, pointer, trackpad, digitizer, consumerControl, other }`
- Produces: `struct CandidateScore: Equatable { let descriptor: HIDDeviceDescriptor; let score: Int; let reasons: [String] }`
- Produces: `protocol HIDDeviceEnumerating { func descriptors() throws -> [HIDDeviceDescriptor] }`
- Produces: `struct CandidateRanker { static func rank(_ descriptors: [HIDDeviceDescriptor]) -> [CandidateScore] }`
- Produces: `static let minimumSelectableScore: Int = 40`

- [ ] **Step 1: Write failing ranking tests**

Create tests for the mandatory safety rules:

```swift
final class CandidateRankingTests: XCTestCase {
    func testKeyboardIsExcludedEvenWhenNameContainsSensor() {
        let keyboard = HIDDeviceDescriptor.fixture(
            name: "Apple Sensor Keyboard",
            vendorID: 0x05AC,
            productID: 1,
            usagePage: 0x01,
            usage: 0x06,
            inputClass: .keyboard
        )

        XCTAssertTrue(CandidateRanker.rank([keyboard]).isEmpty)
    }

    func testLidAngleIdentityRanksAboveGenericAppleDevice() {
        let lid = HIDDeviceDescriptor.fixture(name: "Apple Lid Angle Sensor", vendorID: 0x05AC, productID: 2, usagePage: 0xFF00, usage: 1, inputClass: .other)
        let generic = HIDDeviceDescriptor.fixture(name: "Apple Internal Device", vendorID: 0x05AC, productID: 3, usagePage: 0xFF00, usage: 2, inputClass: .other)

        let ranked = CandidateRanker.rank([generic, lid])

        XCTAssertEqual(ranked.first?.descriptor.name, "Apple Lid Angle Sensor")
        XCTAssertGreaterThanOrEqual(ranked.first?.score ?? 0, CandidateRanker.minimumSelectableScore)
    }

    func testAppleVendorAloneDoesNotMeetThreshold() {
        let generic = HIDDeviceDescriptor.fixture(name: "Apple Internal Device", vendorID: 0x05AC, productID: 3, usagePage: 0xFF00, usage: 2, inputClass: .other)
        let ranked = CandidateRanker.rank([generic])

        XCTAssertLessThan(ranked.first?.score ?? 0, CandidateRanker.minimumSelectableScore)
    }
}
```

Add a test-only `fixture(...)` factory in the test target, not production source.

- [ ] **Step 2: Run ranking tests and verify RED**

Run:

```bash
swift test --filter CandidateRankingTests
```

Expected: compilation fails because descriptor and ranking types do not exist.

- [ ] **Step 3: Implement descriptors and pure ranking**

Define descriptor fields:

```swift
struct HIDDeviceDescriptor: Equatable, Sendable {
    let registryEntryID: UInt64
    let name: String
    let vendorID: Int?
    let productID: Int?
    let usagePage: Int?
    let usage: Int?
    let transport: String?
    let inputClass: HIDInputClass
}
```

Ranking rules must be deterministic:

- Excluded input classes produce no candidate.
- Name tokens `lid`, `angle`, `hinge`, `clamshell` each add `30` once.
- Name token `sensor` adds `10`.
- Nonstandard/vendor-defined usage page (`>= 0xFF00`) adds `10`.
- Apple vendor ID `0x05AC` adds `5`.
- Generic Apple metadata without a lid-related identity remains below `40`.
- Sort by descending score, then ascending registry entry ID.

- [ ] **Step 4: Implement read-only IOHID enumeration adapter**

Implement:

```swift
final class IOHIDDeviceEnumerator: HIDDeviceEnumerating {
    func descriptors() throws -> [HIDDeviceDescriptor]
}
```

Requirements:

- Use `IOHIDManagerCreate`, `IOHIDManagerSetDeviceMatching(..., nil)`, and `IOHIDManagerCopyDevices`.
- Read properties only through `IOHIDDeviceGetProperty`.
- Derive `registryEntryID` from the underlying service.
- Do not open devices during enumeration.
- Classify usages before ranking.
- Release Core Foundation resources through Swift ownership or explicit cleanup as appropriate.

- [ ] **Step 5: Run Task 2 tests and a metadata-only smoke test**

Run:

```bash
swift test --filter CandidateRankingTests
swift test
swift build
```

Add a temporary debug invocation through `main.swift` only if needed to print descriptor count; remove temporary output before review.

- [ ] **Step 6: Review Task 2**

Review requirements:

- No descriptor enumeration opens or writes to an HID device.
- All forbidden input classes are excluded before scoring.
- Apple vendor identity cannot independently cross the selection threshold.
- Ranking reasons explain every awarded score component.
- IOHID object lifetimes are deterministic.

- [ ] **Step 7: Commit Task 2**

```bash
git add Sources/LidMonitor/HIDDeviceDescriptor.swift Sources/LidMonitor/LidSensorDiscovery.swift Sources/LidMonitor/DiagnosticModels.swift Tests/LidMonitorTests/CandidateRankingTests.swift
git commit -m "feat: 加入安全的 HID 候選裝置探索"
```

---

### Task 3: Pure Lid-Angle Decoding Pipeline

**Files:**
- Create: `Sources/LidMonitor/LidAngleDecoder.swift`
- Create: `Tests/LidMonitorTests/LidAngleDecoderTests.swift`
- Modify: `Sources/LidMonitor/DiagnosticModels.swift`

**Interfaces:**
- Produces: `struct HIDReport: Equatable, Sendable { let reportID: UInt32; let bytes: [UInt8]; let timestamp: Date }`
- Produces: `enum AngleDecodeResult: Equatable { case decoded(Double); case unsupported(reportLength: Int); case malformed(String); case outOfRange(Double) }`
- Produces: `protocol LidAngleDecoding { func decode(_ report: HIDReport) -> AngleDecodeResult }`
- Produces: `struct CompositeLidAngleDecoder: LidAngleDecoding`
- Consumes: no hardware adapter.

- [ ] **Step 1: Write failing decoder tests with explicit fixtures**

Create fixtures for an initial bounded decoder that interprets a two-byte little-endian unsigned value in tenths of a degree only when the report length is exactly two bytes:

```swift
final class LidAngleDecoderTests: XCTestCase {
    private let decoder = CompositeLidAngleDecoder(decoders: [UInt16TenthsDecoder()])

    func testTwoByteLittleEndianTenthsDecode() {
        let report = HIDReport(reportID: 0, bytes: [0x10, 0x04], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .decoded(104.0))
    }

    func testUnsupportedLengthIsExplicit() {
        let report = HIDReport(reportID: 0, bytes: [0x01, 0x02, 0x03], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .unsupported(reportLength: 3))
    }

    func testAngleAbovePhysicalLimitIsRejected() {
        let report = HIDReport(reportID: 0, bytes: [0xD0, 0x07], timestamp: .distantPast)
        XCTAssertEqual(decoder.decode(report), .outOfRange(200.0))
    }
}
```

The initial accepted physical range is `0...180` degrees. This decoder is exploratory and must not be presented as authoritative until hardware evidence confirms the report shape.

- [ ] **Step 2: Run decoder tests and verify RED**

Run:

```bash
swift test --filter LidAngleDecoderTests
```

Expected: compilation fails because decoder types do not exist.

- [ ] **Step 3: Implement the pure decoding model**

Implement:

```swift
protocol ReportShapeDecoder: Sendable {
    func supports(_ report: HIDReport) -> Bool
    func decodeSupported(_ report: HIDReport) -> AngleDecodeResult
}

struct UInt16TenthsDecoder: ReportShapeDecoder

struct CompositeLidAngleDecoder: LidAngleDecoding {
    let decoders: [any ReportShapeDecoder]
    func decode(_ report: HIDReport) -> AngleDecodeResult
}
```

Rules:

- Never index bytes without a preceding exact shape check.
- Never silently clamp values.
- Preserve unsupported versus malformed versus out-of-range distinctions.
- Keep captured-byte interpretation isolated from CLI and IOHID code.

- [ ] **Step 4: Run Task 3 tests**

Run:

```bash
swift test --filter LidAngleDecoderTests
swift test
```

Expected: all decoder tests and all existing tests pass.

- [ ] **Step 5: Review Task 3**

Review requirements:

- Decoder is pure and deterministic.
- Unsupported report shapes remain visible to the operator.
- The initial decoder is labeled exploratory in code comments and README planning notes.
- No guessed offset or byte order is hidden outside a named decoder.
- Tests cover valid, unsupported, malformed where applicable, and out-of-range paths.

- [ ] **Step 6: Commit Task 3**

```bash
git add Sources/LidMonitor/LidAngleDecoder.swift Sources/LidMonitor/DiagnosticModels.swift Tests/LidMonitorTests/LidAngleDecoderTests.swift
git commit -m "feat: 建立可測試的角度解碼管線"
```

---

### Task 4: Clamshell State and Read-Only HID Report Streaming

**Files:**
- Create: `Sources/LidMonitor/ClamshellStateReader.swift`
- Create: `Sources/LidMonitor/HIDReportStream.swift`
- Modify: `Sources/LidMonitor/DiagnosticModels.swift`

**Interfaces:**
- Produces: `enum ClamshellState: Equatable { case open; case closed; case unavailable }`
- Produces: `protocol ClamshellStateReading { func currentState() -> ClamshellState }`
- Produces: `final class IORegistryClamshellStateReader: ClamshellStateReading`
- Produces: `protocol HIDReportStreaming: AnyObject { func start(onReport: @escaping @Sendable (HIDReport) -> Void) throws; func stop() }`
- Produces: `final class IOHIDReportStream: HIDReportStreaming`
- Consumes: `HIDDeviceDescriptor` from Task 2 and `HIDReport` from Task 3.

- [ ] **Step 1: Implement clamshell state reader**

Use IORegistry read-only traversal to locate `AppleClamshellState`. The public interface must return `.unavailable` for missing or malformed properties rather than throwing or crashing.

Required method:

```swift
final class IORegistryClamshellStateReader: ClamshellStateReading {
    func currentState() -> ClamshellState
}
```

- [ ] **Step 2: Implement read-only report stream lifecycle**

`IOHIDReportStream` must:

- Resolve the device by the selected descriptor's registry entry ID.
- Call `IOHIDDeviceOpen` with read-only/default options.
- Allocate a report buffer sized from `kIOHIDMaxInputReportSizeKey`, with a defensible fallback and upper safety bound.
- Register only `IOHIDDeviceRegisterInputReportCallback`.
- Schedule the device on a dedicated run loop.
- Copy callback bytes into `[UInt8]` before invoking Swift code.
- Stop, unschedule, close, and release deterministically.
- Never call `IOHIDDeviceSetReport` or request output/feature reports.

Required initializer:

```swift
init(descriptor: HIDDeviceDescriptor) throws
```

- [ ] **Step 3: Add lifecycle-focused seams for testing**

Do not attempt to unit test real IOHID callbacks. Instead, isolate resource control behind an internal adapter protocol:

```swift
protocol HIDDeviceSession: AnyObject {
    func open() throws
    func registerInputCallback(_ callback: @escaping @Sendable (UInt32, [UInt8]) -> Void) throws
    func run()
    func stop()
    func close()
}
```

Use a fake session in tests to verify that `stop()` and `close()` are called once when the stream terminates. Add these tests to `LidAngleDecoderTests.swift` only if they remain focused; otherwise create `HIDReportStreamTests.swift` and update the file map in the implementation review.

- [ ] **Step 4: Run full tests and build**

Run:

```bash
swift test
swift build
```

Expected: exit `0` with no hardware required for unit tests.

- [ ] **Step 5: Perform a bounded metadata/open smoke test**

Add a temporary developer-only path or XCTest-disabled harness that opens only the selected high-confidence candidate, waits no more than five seconds for an input report, and closes it. Do not commit temporary bypasses or threshold reductions.

Record whether the open attempt succeeds, is denied, or receives no report. This is evidence, not yet the final hardware validation.

- [ ] **Step 6: Review Task 4**

Review requirements:

- No HID write API exists anywhere in the codebase.
- The selected device must already meet the confidence threshold.
- Buffer sizing is bounded.
- Callback data is copied before crossing into Swift ownership.
- All open/schedule/run resources have paired stop/unschedule/close cleanup.
- Missing clamshell property produces `.unavailable`.

- [ ] **Step 7: Commit Task 4**

```bash
git add Sources/LidMonitor/ClamshellStateReader.swift Sources/LidMonitor/HIDReportStream.swift Sources/LidMonitor/DiagnosticModels.swift Tests
git commit -m "feat: 串接唯讀 HID 報告與闔蓋狀態"
```

---

### Task 5: Deterministic Output and End-to-End CLI Orchestration

**Files:**
- Create: `Sources/LidMonitor/OutputFormatter.swift`
- Create: `Tests/LidMonitorTests/OutputFormatterTests.swift`
- Modify: `Sources/LidMonitor/main.swift`
- Modify: `Sources/LidMonitor/CLI.swift`
- Modify: `Sources/LidMonitor/LidSensorDiscovery.swift`

**Interfaces:**
- Produces: `struct OutputFormatter`
- Produces: `protocol DiagnosticClock { var now: Date { get } }`
- Consumes: all Task 1–4 interfaces.

- [ ] **Step 1: Write failing deterministic formatter tests**

Create tests using a fixed ISO-8601 timestamp:

```swift
final class OutputFormatterTests: XCTestCase {
    func testDecodedWatchLine() {
        let formatter = OutputFormatter(timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
        let date = Date(timeIntervalSince1970: 1_721_966_201)

        XCTAssertEqual(
            formatter.watchLine(timestamp: date, result: .decoded(103.4), rawBytes: nil, clamshell: .open),
            "2024-07-26T18:36:41+08:00 angle=103.4 clamshell=open"
        )
    }

    func testUnsupportedLineIncludesLength() {
        let formatter = OutputFormatter(timeZone: TimeZone(secondsFromGMT: 0)!)
        let line = formatter.watchLine(timestamp: .distantPast, result: .unsupported(reportLength: 8), rawBytes: nil, clamshell: .unavailable)
        XCTAssertTrue(line.contains("angle=unsupported"))
        XCTAssertTrue(line.contains("reportLength=8"))
        XCTAssertTrue(line.contains("clamshell=unavailable"))
    }
}
```

Calculate and correct the fixed expected timestamp during implementation if the epoch literal does not correspond to the written ISO value; the final test must use a verified matching pair rather than weakening the assertion.

- [ ] **Step 2: Run formatter tests and verify RED**

Run:

```bash
swift test --filter OutputFormatterTests
```

Expected: compilation fails because `OutputFormatter` does not exist.

- [ ] **Step 3: Implement formatter and list output**

Formatter responsibilities:

- Stable ISO-8601 timestamps with local numeric offset.
- One decimal place for decoded angles.
- Uppercase hexadecimal raw bytes separated by spaces when `--raw` is active.
- Explicit `open`, `closed`, and `unavailable` clamshell values.
- Candidate list includes score, reasons, name, registry ID, vendor/product IDs, usage page/usage, transport, and exclusion status where relevant.

- [ ] **Step 4: Compose the real CLI flow in `main.swift`**

List mode:

1. Print runtime environment.
2. Enumerate descriptors.
3. Rank safe candidates.
4. Print candidates and reasons.
5. Exit `69` when none meet the threshold; otherwise exit `0` without opening a device.

Watch mode:

1. Print runtime environment and candidate summary.
2. Refuse to open when the top candidate is below threshold.
3. Construct `IOHIDReportStream`, decoder, clamshell reader, and formatter.
4. On each report, decode and print one line.
5. Respect `--raw` and `--duration`.
6. Install `SIGINT` handling that calls `stop()` once and exits `0`.
7. Map usage, unavailable, I/O, and unexpected failures to the exact exit codes.

Do not call `exit` from domain components; only the composition root maps outcomes to process exit.

- [ ] **Step 5: Run Task 5 tests and CLI checks**

Run:

```bash
swift test
swift build
swift run macbook-lid-monitor --help || test $? -eq 64
swift run macbook-lid-monitor --list
```

Expected:

- All tests pass.
- Build exits `0`.
- Invalid or unsupported help behavior is intentionally documented; preferably add `--help` as successful usage if implemented, but do not silently treat it as watch mode.
- List mode never opens a device.

- [ ] **Step 6: Review Task 5**

Review requirements:

- Output is deterministic and actionable.
- `--list` cannot open a HID device.
- `--raw` and duration behavior match the spec.
- Signal handling is idempotent.
- Exit codes match the spec exactly.
- No hardware or process-global logic leaked into pure formatter/parser tests.

- [ ] **Step 7: Commit Task 5**

```bash
git add Sources/LidMonitor Tests/LidMonitorTests
git commit -m "feat: 完成診斷 CLI 與輸出流程"
```

---

### Task 6: Operator Script, Documentation, and Bounded Hardware Validation

**Files:**
- Create: `scripts/run-diagnostic.sh`
- Create: `README.md`
- Create: `docs/validation/2026-07-26-m1-pro-lid-angle.md`
- Modify: any source or tests only when hardware evidence identifies a verified report format or defect.

**Interfaces:**
- Consumes: completed executable from Tasks 1–5.
- Produces: reproducible operator commands and a hardware evidence record.

- [ ] **Step 1: Create the operator script**

Create `scripts/run-diagnostic.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release
exec .build/release/macbook-lid-monitor "$@"
```

Mark it executable:

```bash
chmod +x scripts/run-diagnostic.sh
```

- [ ] **Step 2: Write README operating and safety guidance**

Document:

- Purpose and diagnostic-only scope.
- Requirements: Apple Silicon MacBook, macOS 13+, Swift 6.x command-line tools.
- `--list`, default watch, `--watch`, `--raw`, and `--duration` examples.
- Exit-code meanings.
- Expected decoded, unsupported, access-denied, and no-candidate output.
- Permission guidance that reports observed errors without promising a particular Privacy & Security permission.
- Explicit statement that the initial decoder is exploratory until validated.
- Removal by stopping the process and deleting the project directory.
- Warning that Phase 1 never sleeps the Mac automatically.

- [ ] **Step 3: Run pre-hardware full validation**

Run:

```bash
swift package clean
swift test
swift build -c release
./scripts/run-diagnostic.sh --list
git diff --check
```

Expected:

- Tests pass with zero failures.
- Release build exits `0`.
- List mode either identifies safe candidates or exits `69` with actionable metadata.
- No uncommitted temporary harness remains.

- [ ] **Step 4: Perform the bounded hardware procedure**

Run:

```bash
./scripts/run-diagnostic.sh --watch --raw --duration 120
```

Operator procedure:

1. Hold the display near fully open and capture at least five reports.
2. Move to a middle angle and capture at least five reports.
3. Move to approximately 15 degrees and capture at least five reports.
4. Move as close to fully closed as practical without relying on automatic sleep.
5. Reopen and verify whether reports resume.
6. Record the contemporaneous clamshell state at each position.

Do not lower candidate thresholds or grant privileges merely to force a result.

- [ ] **Step 5: Classify the result using evidence**

Write `docs/validation/2026-07-26-m1-pro-lid-angle.md` with one of these conclusions:

```text
A. Raw values change consistently; decoded angle is plausible; clamshell remains open.
B. Raw values change but current decoder is unsupported or implausible.
C. Candidate opens but raw values remain fixed across three positions.
D. No sufficiently confident candidate is discoverable.
E. Candidate is discoverable but access is denied or streaming fails.
```

Include command, environment, candidate metadata, position-by-position evidence, clamshell state, and whether the stream resumed after reopening. Do not include unrelated HID input or personal data.

- [ ] **Step 6: Add or correct a decoder only when captured evidence supports it**

When result `B` occurs:

1. Add anonymized sensor-byte fixtures to `LidAngleDecoderTests.swift`.
2. Run the new test and verify it fails.
3. Add a narrowly named decoder for the observed report shape.
4. Run the test and verify it passes.
5. Repeat the hardware run to confirm monotonic, physically plausible values.

When results `C`, `D`, or `E` occur, do not invent a decoder. Follow the bounded second investigation from the spec and stop if it yields no safe read-only path.

- [ ] **Step 7: Perform Task 6 review and commit**

Review requirements:

- Script is portable within the project and uses release output.
- README does not overpromise sensor support or permissions.
- Validation record contains evidence for three or more positions.
- No auto-sleep or persistent service exists.
- Any decoder added after hardware capture has a verified red-green test and matching hardware evidence.

Commit:

```bash
git add README.md scripts docs/validation Sources Tests
git commit -m "docs: 完成 M1 Pro 闔蓋角度實機驗證"
```

---

## Whole-Phase Final Review

- [ ] **Step 1: Verify repository safety boundaries**

Run:

```bash
! grep -RInE 'IOHIDDeviceSetReport|pmset sleepnow|IOPMSleepSystem|nvram|LaunchAgent|SMJobBless|AuthorizationExecuteWithPrivileges' Sources scripts Package.swift
```

Expected: no matches.

- [ ] **Step 2: Verify full build and tests from clean state**

Run:

```bash
swift package clean
swift test
swift build -c release
git diff --check
```

Expected: all commands exit `0` and tests report zero failures.

- [ ] **Step 3: Review implementation against every spec section**

Create `docs/superpowers/reviews/2026-07-26-lid-angle-diagnostic-final-review.md` containing:

- Spec coverage matrix for sections 1–13.
- Task commit list.
- Open findings grouped by P0/P1/P2.
- Hardware result classification A–E.
- Explicit statement whether a separate auto-sleep design is justified.

Final gate:

```text
Open P0 = 0
Open P1 = 0
```

- [ ] **Step 4: Fix findings and rerun complete validation**

Every final-review finding must be fixed or explicitly deferred with reason. After fixes, rerun the clean test/build/safety commands and update the review with fresh evidence.

- [ ] **Step 5: Commit the final review**

```bash
git add docs/superpowers/reviews Sources Tests README.md scripts
git commit -m "docs: 完成闔蓋角度診斷總審查"
```

## Execution Recommendation

Use **subagent-driven development** when independent reviewers are available, with a fresh implementer and reviewer per task. In this bridge-controlled session, inline execution is also acceptable as long as every Task follows the governance contract above and no task proceeds with open P0/P1 findings.
