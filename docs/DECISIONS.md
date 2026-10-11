# GitGet decisions and compatibility evidence

This file records what the diagnostic milestone relies on, where the evidence
came from, and what is still unverified. Later agents should read it before
changing the package layout.

## Milestone 2: environment report utility

### Package layout

The ZIP is extracted at the root of the microSD partition that holds the ROM
folders (on ArkOS this is the partition mounted at `/roms`). Paths in the ZIP:

```
ports/GitGet Diagnostic.sh
ports/gitget-diag/README.txt
ports/gitget-diag/MANIFEST.txt
```

Evidence for the layout:

- PortMaster documents that a port is a launcher script named like
  `Port Name.sh` plus a port directory of the same purpose, and that on ArkOS
  the contents of a port ZIP are extracted into the `/roms/ports` folder (or
  `/roms2/ports` when a second card holds the ROMs).
  Sources: https://portmaster.games/packaging.html and
  https://github.com/christianhaitian/PortMaster
- The ArkOS autoinstall folder is `/roms/tools/PortMaster/autoinstall/`
  (source: https://github.com/lowlevel-1989/pokemmo-port). GitGet does not use
  it because this is a plain launcher, not a PortMaster-installed port.

### Why the launcher does not source PortMaster's control.txt

Normal PortMaster launchers `source` `control.txt`. That file sets up the
controller layer and can run privileged commands, which would break the
"read-only" requirement. The diagnostic only locates PortMaster folders and
greps variable names out of `control.txt` without running it.

### Report location

Preferred: `ports/gitget-diag/GitGet_Device_Report.txt`. Fallbacks, in order:
the launcher's own folder, `/roms`, `/roms2`, `/tmp`. The folder used is
printed on the handheld screen.

### Privacy decisions

Not recorded: MAC addresses, IP addresses, Wi-Fi network names or keys, CPU
serial numbers, input device unique IDs, button presses. Mount options that
can carry credentials are redacted. Environment variables are printed only
from a fixed list.

### Unverified assumptions (no physical R36S evidence yet)

1. Writing to `/dev/tty1` shows text on the handheld screen under ArkOS. A web
   search did not turn up a source; this is the common pattern in ArkOS shell
   tools but is unconfirmed. If it fails, the report is still written and the
   screen simply stays on EmulationStation.
2. EmulationStation lists a new `.sh` in the Ports menu after a restart of
   EmulationStation or a reboot.
3. The launcher runs correctly whether EmulationStation executes it directly
   (needs a `#!/bin/sh` first line and an executable bit, which the card's
   file system may or may not preserve) or passes it to a shell. The script
   does not depend on being executable when run as `sh script`.
4. The controller cannot dismiss the final screen. It closes on a timer
   (20 seconds). Controller dismissal needs `gptokeyb`, which comes from
   PortMaster and was left out to stay read-only and dependency free.
5. Whether the R36S userspace is aarch64 or armhf is exactly what the report
   will show (ELF header of `/bin/sh` and `dpkg --print-architecture`).

### What the PC-side check covers

`tests/check_diagnostic.sh`: shell syntax, portability patterns, line endings,
a sandboxed run, report sections, a sensitive-pattern scan, ZIP layout,
permissions, manifest and checksum. It does not prove anything about the
physical device.
