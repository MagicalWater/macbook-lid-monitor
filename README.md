# macbook-lid-monitor

`macbook-lid-monitor` is a read-only macOS diagnostic tool for checking whether a modern MacBook's lid-angle HID sensor still reports usable values when normal clamshell sleep detection is unreliable.

Phase 1 is diagnostic only. It does not put the Mac to sleep, change power settings, modify NVRAM, install a LaunchAgent, request administrator privileges, or write HID reports.

## Requirements

- Apple Silicon MacBook
- macOS 13.0 or newer
- Swift 6.x through Xcode Command Line Tools

The first validated machine is an M1 Pro MacBook running macOS 26.5.2.

## Usage

List ranked read-only candidates without opening a device:

```bash
./scripts/run-diagnostic.sh --list
```

Watch the best high-confidence candidate:

```bash
./scripts/run-diagnostic.sh --watch
```

Include copied raw report bytes:

```bash
./scripts/run-diagnostic.sh --watch --raw
```

Stop automatically after a fixed number of seconds:

```bash
./scripts/run-diagnostic.sh --watch --raw --duration 120
```

No arguments defaults to watch mode. Press `Ctrl+C` to stop an unlimited watch.

## Output

Decoded sample:

```text
2026-07-26T11:01:58+08:00 angle=173.0 raw=01 AD 00 clamshell=open
```

Unsupported report shape:

```text
2026-07-26T11:00:33+08:00 angle=unsupported reportLength=3 raw=01 AC 00 clamshell=open
```

Candidate entries include score, whether the threshold is met, registry ID, vendor/product IDs, usage page/usage, transport, and scoring reasons.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | Successful list or completed watch |
| `64` | Invalid command-line usage |
| `69` | No sufficiently confident candidate or HID enumeration unavailable |
| `70` | Unexpected internal failure |
| `74` | HID device open or streaming failure |

## Sensor identity and decoder status

The validated M1 Pro exposes the selected sensor as:

```text
Vendor ID:  0x05AC
Product ID: 0x8104
Usage Page: 0x0020
Usage:      0x008A
Transport:  SPU
```

Observed input reports use three bytes: report ID `1`, a low angle byte, and a high angle byte. For example, `01 AC 00` decodes to `172°`. This decoder is narrowly tied to the captured M1 Pro evidence. The older two-byte tenths decoder remains exploratory and is not treated as authoritative without matching hardware evidence.

## Permissions and failures

The program does not escalate privileges. If macOS denies HID access, it reports the actual open error and exits. The required Privacy & Security surface can vary by macOS release, so this project does not promise that enabling a particular permission will solve every access failure.

When no candidate reaches the threshold, use `--list` output as evidence. Do not lower the threshold merely to force a device open.

## Safety boundaries

- No HID write or feature-report request
- No automatic sleep
- No persistent service
- No unrelated keyboard or trackpad capture
- Input callback bytes are copied before decoding

Phase 1 cannot repair a broken clamshell sensor. Its purpose is to determine whether the independent angle sensor can support a later, separately designed auto-sleep workaround.

## Removal

Stop the process and delete:

```text
/Users/water/Developer/projects/macbook-lid-monitor
```

No system settings or persistent services are installed by Phase 1.
