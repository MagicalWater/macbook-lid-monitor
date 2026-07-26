# MacBook Lid Angle Diagnostic — Design

## 1. Purpose

Build a small, standalone macOS command-line diagnostic tool that determines whether the MacBook's raw lid-angle sensor still produces usable data even though macOS is not generating normal clamshell sleep events.

The first phase is diagnostic only. It must not trigger sleep, change power settings, install background services, modify NVRAM, or require SIP changes.

## 2. Success Criteria

The tool is considered useful when it can do at least one of the following:

1. Discover a candidate lid-angle HID device and continuously output a changing angle while the display is opened and closed.
2. Discover a candidate device but show that its raw values remain fixed or invalid.
3. Clearly report that no compatible lid-angle device can be accessed, including enough device metadata to support a second investigation.

The diagnostic result must distinguish these cases:

- Raw angle changes while `AppleClamshellState` does not change.
- Raw angle and `AppleClamshellState` both fail to change.
- No compatible sensor is discoverable.

## 3. Scope

### Included

- A Swift Package executable named `macbook-lid-monitor`.
- Native macOS access through IOKit and IOHID APIs.
- Enumeration of HID services that may represent the lid-angle sensor.
- Output of identifying metadata such as registry name, vendor ID, product ID, usage page, usage, and transport when available.
- Continuous output of raw reports and interpreted angle values when decoding succeeds.
- Parallel sampling of `AppleClamshellState` for comparison.
- A small testable decoding layer separated from hardware access.
- A shell script for building and running the diagnostic.
- Documentation covering expected output, limitations, and removal.

### Platform Baseline

- Target hardware: Apple Silicon MacBook Pro, validated first on the user's M1 Pro machine.
- Minimum deployment target: macOS 13.0.
- Toolchain: Swift 6.x through the system Xcode Command Line Tools.
- Package type: Swift Package Manager executable with no third-party runtime dependency.
- Initial release version: `0.1.0`, declared once in package source and reused by CLI output.

### Excluded

- Automatic sleep.
- LaunchAgent or login-item installation.
- Menu bar UI.
- Power-management setting changes.
- Kernel extensions, DriverKit extensions, SIP changes, or private framework injection.
- Support for non-Apple laptops.

## 4. Technical Approach

Use a native Swift command-line executable because it provides direct access to macOS frameworks, requires no additional runtime, and can later be extended into a lightweight background utility if the sensor data is reliable.

The tool will use two discovery paths:

1. IOHIDManager matching and enumeration.
2. IORegistry inspection for candidate services and metadata.

The implementation must avoid hard-coding a single product identifier as the only matching rule. Candidate ranking should consider:

- Device or registry names containing lid, angle, hinge, clamshell, or sensor-related terms.
- Relevant HID usage pages and usages.
- Known Apple vendor metadata.
- Report structure compatible with known lid-angle payloads.

Because the lid-angle interface is not a stable public API, decoding must be isolated behind a protocol so additional report formats can be added without changing device discovery or CLI behavior.

## 5. Proposed Project Structure

```text
macbook-lid-monitor/
├── Package.swift
├── README.md
├── Sources/
│   └── LidMonitor/
│       ├── main.swift
│       ├── CLI.swift
│       ├── LidSensorDiscovery.swift
│       ├── HIDDeviceDescriptor.swift
│       ├── HIDReportStream.swift
│       ├── LidAngleDecoder.swift
│       ├── ClamshellStateReader.swift
│       └── DiagnosticModels.swift
├── Tests/
│   └── LidMonitorTests/
│       ├── LidAngleDecoderTests.swift
│       └── CandidateRankingTests.swift
├── scripts/
│   └── run-diagnostic.sh
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-07-26-lid-angle-diagnostic-design.md
```

## 6. Components

### CLI

Responsibilities:

- Parse diagnostic options.
- Print environment and device-discovery results.
- Start and stop report streaming.
- Render timestamped angle, raw bytes, and clamshell state.
- Exit cleanly on `Ctrl+C`.

Initial options:

```text
--list                 List candidate HID devices and exit.
--watch                Continuously watch the best candidate.
--raw                  Include raw report bytes.
--duration <seconds>   Stop automatically after a fixed duration.
```

`--watch` will be the default behavior when no mode is supplied.

Argument rules:

- `--list` and `--watch` are mutually exclusive explicit modes.
- `--raw` is valid only with watch mode, including the implicit default watch mode.
- `--duration` accepts a finite value greater than `0` and is valid only with watch mode.
- Unknown options, missing values, invalid numbers, and conflicting modes must print usage to standard error and exit with code `64`.
- `Ctrl+C` during watch mode is a successful operator-requested stop and exits with code `0`.

### LidSensorDiscovery

Responsibilities:

- Enumerate accessible HID devices.
- Normalize device metadata.
- Rank likely lid-angle candidates.
- Explain why each candidate received its rank.

Discovery must remain read-only.

Candidate safety rules:

- Devices classified as keyboard, keypad, mouse, pointer, trackpad, digitizer, or consumer-control input must be excluded before ranking.
- A candidate must expose at least one non-keyboard/non-pointing HID usage or an IORegistry identity containing a lid, angle, hinge, clamshell, or sensor term.
- Apple vendor metadata may increase confidence but must not be sufficient by itself.
- If the highest-ranked candidate does not meet the minimum confidence threshold, the CLI must report all candidate metadata and stop rather than opening a low-confidence device.

### HIDReportStream

Responsibilities:

- Open the selected HID device.
- Register input-report callbacks.
- Copy report bytes into safe Swift values.
- Close resources deterministically.

It must not send output or feature reports unless a later investigation proves that a read request is strictly required. Any such change would require a design update before implementation.

### LidAngleDecoder

Responsibilities:

- Convert raw HID reports into a typed decoding result.
- Support multiple decoders selected by report shape.
- Return explicit states: decoded, unsupported format, malformed, or out of range.

The decoder must be pure and unit-testable with captured byte fixtures.

### ClamshellStateReader

Responsibilities:

- Read the current `AppleClamshellState` from IORegistry.
- Return unavailable rather than crashing when the property cannot be found.

### DiagnosticModels

Defines immutable value types for device descriptors, candidate scores, raw reports, decoded samples, and diagnostic errors.

## 7. Data Flow

```text
IOHID / IORegistry
      ↓
LidSensorDiscovery
      ↓
Ranked candidate list
      ↓
Selected HID device
      ↓
HIDReportStream
      ↓
Raw report bytes ──→ optional raw output
      ↓
LidAngleDecoder
      ↓
Angle sample
      ↓
CLI output + AppleClamshellState comparison
```

## 8. Output Format

Startup output should identify the environment and selected device:

```text
macbook-lid-monitor 0.1.0
Architecture: arm64
macOS: 26.x
Candidates found: 1
Selected: <device name>
VendorID: 0x05AC
ProductID: 0x....
UsagePage: 0x....
Usage: 0x....
```

Watch output should be concise and timestamped:

```text
2026-07-26T10:30:01+08:00 angle=103.4 clamshell=open
2026-07-26T10:30:02+08:00 angle=72.8 clamshell=open
2026-07-26T10:30:03+08:00 angle=18.1 clamshell=open
2026-07-26T10:30:04+08:00 angle=2.6 clamshell=open
```

When decoding is unavailable:

```text
2026-07-26T10:30:04+08:00 angle=unsupported reportLength=8 clamshell=open
```

## 9. Error Handling

The executable must provide actionable errors for:

- No candidate HID devices.
- Candidate found but access denied.
- Device disappears while watching.
- Unsupported report format.
- Invalid decoded angle.
- Missing clamshell registry property.

Hardware-access failures must not crash the process. The CLI should exit non-zero for startup failures and continue with a warning for individual malformed reports.

Exit codes:

- `0`: successful list/watch completion or operator cancellation with `Ctrl+C`.
- `64`: invalid command-line usage.
- `69`: no compatible or sufficiently confident sensor candidate.
- `74`: candidate found but the device cannot be opened or streaming fails.
- `70`: unexpected internal failure.

## 10. Permissions and Safety

The first run should not request administrator privileges by default.

If macOS denies HID access, the tool must report the denial and document the relevant Privacy & Security permission rather than automatically escalating privileges.

The documentation must not promise that granting Input Monitoring is required. It should report the observed denial first and explain that macOS permission behavior can differ by OS release and device classification.

The tool must not:

- Write to HID devices.
- Change system power settings.
- Call sleep APIs.
- Install persistent services.
- Collect unrelated keyboard or pointing-device input.

Candidate matching must be narrow enough to avoid opening the internal keyboard or trackpad as the selected sensor.

## 11. Testing Strategy

### Unit tests

- Known raw report fixtures decode into expected angles.
- Malformed reports return explicit errors.
- Out-of-range values are rejected.
- Candidate ranking favors lid-angle-like devices and rejects keyboard/trackpad devices.
- CLI formatting remains deterministic.

### Hardware validation

1. Run `--list` and record discovered candidates.
2. Run `--watch --raw` with the display fully open.
3. Slowly move through several angles.
4. Close the display to near zero degrees without relying on automatic sleep.
5. Reopen it and compare raw values, decoded angle, and `AppleClamshellState`.

The first hardware run is exploratory. Captured reports may be converted into anonymized test fixtures containing only sensor bytes and no personal data.

Hardware validation is successful only when the run records all of the following:

- At least three clearly different physical lid positions.
- Corresponding raw reports or explicit evidence that reports remain unchanged.
- The decoded angle or decoder status for each position.
- The contemporaneous `AppleClamshellState` value.
- Whether the sensor stream resumes after reopening the display.

## 12. Decision After Diagnostic

### Raw angle changes correctly

Proceed to a separate design for an optional local auto-sleep service with debounce, cooldown, manual disable, and safe recovery behavior.

### Raw angle is fixed or invalid

Conclude that software cannot reliably infer lid closure from this sensor path. Do not build auto-sleep behavior from unreliable input.

### No sensor is accessible

Perform one bounded second investigation consisting of IOHID metadata inspection, IORegistry metadata inspection, and observed permission-denial analysis. If those three checks do not identify a safe read-only path, stop rather than introducing kernel-level, DriverKit, write-report, administrator-escalation, or SIP-dependent workarounds.

## 13. Removal

The diagnostic project is self-contained. Removal consists of stopping the process and deleting:

```text
~/Developer/projects/macbook-lid-monitor
```

No system settings or persistent services should need cleanup after Phase 1.
