---
title: "NVIDIA RTD3 source qualification"
type: review
status: draft
review: pending
created: 2026-11-16
updated: 2026-11-20
tags: [review, gpu, power]
aliases: [NVIDIA 1512 preflight]
---

# NVIDIA RTD3 source qualification

[Issue #195](https://github.com/subculture-collective/subarchy/issues/195)
remains open under [roadmap #230](https://github.com/subculture-collective/subarchy/issues/230).
The November 15 Sputnik battery comparison establishes a kernel-dependent
result: Zen `7.3.4-zen2-2-zen` failed P9; LTS `6.18.63-3-lts` passed with
the same NVIDIA `620.70.06`, `DynamicPowerManagement=2` and PCI
`power/control=auto`. The dated readings are in [[first-install#NVIDIA runtime power (#195, P9)]].
They do not establish which kernel operation failed on Sputnik.

Later on November 16 a candidate was built for both kernels and booted in
a disposable VM; see [[#Candidate builds and VM boots, November 16]]. The
candidate has not been installed on Sputnik, and the November 17 battery
test on the stock driver failed again on Zen. Upstream PR #1512 has a newer
head than the one examined here; a comparison recorded on #195 on November
20 found it makes the same change as the candidate's patch.

This November 16 investigation on Kvant checks source applicability and
dependencies. It does not qualify a patched driver. Keep the installed LTS
entry as the tested workaround and retain Zen as the default. The existing
Subarchy power option and udev rules have already been tested; applying
them again does not advance the Zen failure.

## Exact sources and result

Checked on November 16, 2026 UTC:

| Source | Immutable revision | Result |
|---|---|---|
| Latest NVIDIA release, `620.70.06` | [`e6a2e01579fbbd1ca2ed43fef2ee2589e9bd8bd9`](https://github.com/NVIDIA/open-gpu-kernel-modules/commit/e6a2e01579fbbd1ca2ed43fef2ee2589e9bd8bd9) | Still uses plain `filp_open()` in `nv_get_pci_sysfs_config()` |
| NVIDIA [PR #1512](https://github.com/NVIDIA/open-gpu-kernel-modules/pull/1512) | [`369378dc1552ae46f7f95a598a085c0025e464b3`](https://github.com/NVIDIA/open-gpu-kernel-modules/commit/369378dc1552ae46f7f95a598a085c0025e464b3) | Open, unmerged; GitHub reports `mergeable=false`, `mergeable_state=dirty` |
| Proposal's parent | [`ca2d03e6fafd4d4b56b383497d931c25b283bfcf`](https://github.com/NVIDIA/open-gpu-kernel-modules/commit/ca2d03e6fafd4d4b56b383497d931c25b283bfcf) | Exact proposal passes `git apply --check` |
| Linux nullfs change | [`32750c77e811dba81eb92abf9182b1f424255d3a`](https://github.com/torvalds/linux/commit/32750c77e811dba81eb92abf9182b1f424255d3a) | Starts kernel threads with an isolated filesystem root |
| Linux scoped filesystem helper | [`67c54d1d730a8b7a43f2560dcea9b7dc95fba1cd`](https://github.com/torvalds/linux/commit/67c54d1d730a8b7a43f2560dcea9b7dc95fba1cd) | Introduces `scoped_with_init_fs()` |
| Linux init filesystem pointer | [`9a8e296958884b807a02759975170b6559901242`](https://github.com/torvalds/linux/commit/9a8e296958884b807a02759975170b6559901242) | Initializes `userspace_init_fs` and wires up the scoped override |

The proposed mechanism fits the source. During driver registration,
[`nv_pci_probe()`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e6a2e01579fbbd1ca2ed43fef2ee2589e9bd8bd9/kernel-open/nvidia/nv-pci.c#L1671)
can delegate to a kernel thread. Its PCI config-file open is absolute and
unscoped. In
[`nv_dynamic_power_available()`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e6a2e01579fbbd1ca2ed43fef2ee2589e9bd8bd9/kernel-open/nvidia/nv.c#L5826),
an unset `sysfs_config_file` makes runtime power unavailable when runtime
PM is compiled in. Other checks in the open path can also leave that pointer
unset; an unsupported RTD3 status alone does not prove `-ENOENT`.

The exact patch **does not apply unchanged to 620.70.06**. Only its first
hunk's trailing context conflicts: `linux/kthread.h` is now followed by
the `NV_SEQ_READ_ITER_PRESENT` includes rather than `linux/clk.h` and its
neighbors. Replacing those three context lines, without changing any added
or removed lines, makes all four hunks pass `git apply --check`. The offsets
are +9, +42 and -1009 lines in `nv-pci.c`, and +3 in `nvidia.Kbuild`.
This agrees with the
[upstream tester's context correction](https://github.com/NVIDIA/open-gpu-kernel-modules/pull/1512#issuecomment-6908067908).
Their reported runtime success is on other laptops, not Sputnik.

## Reproduce the source check

Run from the repository root with Python 3 and Git. This downloads six
small files into a fresh temporary directory, checks both source revisions,
and writes a context-adjusted patch there for inspection. It neither applies
the patch nor builds or installs a module. Check free disk space first.

```sh
df -h /tmp
python3 - <<'PY'
from pathlib import Path
import hashlib
import subprocess
import tempfile
from urllib.request import urlopen

work = Path(tempfile.mkdtemp(prefix="subarchy-rtd3-source-"))
repo = "https://raw.githubusercontent.com/NVIDIA/open-gpu-kernel-modules"
refs = {
    "parent": "ca2d03e6fafd4d4b56b383497d931c25b283bfcf",
    "release": "e6a2e01579fbbd1ca2ed43fef2ee2589e9bd8bd9",
}
for name, ref in refs.items():
    for filename in ("nv-pci.c", "nvidia.Kbuild"):
        path = work / name / "kernel-open/nvidia" / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        with urlopen(f"{repo}/{ref}/kernel-open/nvidia/{filename}", timeout=30) as response:
            path.write_bytes(response.read())
with urlopen(f"{repo}/{refs['release']}/kernel-open/conftest.sh", timeout=30) as response:
    (work / "release/kernel-open/conftest.sh").write_bytes(response.read())
url = "https://github.com/NVIDIA/open-gpu-kernel-modules/commit/369378dc1552ae46f7f95a598a085c0025e464b3.patch"
with urlopen(url, timeout=30) as response:
    original = response.read()
assert hashlib.sha256(original).hexdigest() == "d20d5d591ae206273b055e93630627ec5cc04d4bb08cf97479f5aad9ca0ab35f"
(work / "1512.patch").write_bytes(original)
old = " #include <linux/clk.h>\n #include <linux/device.h>\n #include <linux/jiffies.h>"
new = " #if defined(NV_SEQ_READ_ITER_PRESENT)\n #include <linux/seq_file.h>\n #include <linux/kernfs.h>"
text = original.decode()
assert text.count(old) == 1
adjusted = text.replace(old, new)
assert [line for line in text.splitlines() if line.startswith(("+", "-"))] == [
    line for line in adjusted.splitlines() if line.startswith(("+", "-"))
]
(work / "1512-620-context.patch").write_text(adjusted)
for tree, patch, expected in (
    ("parent", "1512.patch", 0),
    ("release", "1512.patch", 1),
    ("release", "1512-620-context.patch", 0),
):
    result = subprocess.run([
        "git", "-C", str(work / tree), "apply", "--check", "--verbose", str(work / patch)
    ], capture_output=True, text=True)
    print(tree, patch, "exit", result.returncode)
    print(result.stdout + result.stderr)
    assert result.returncode == expected
print("Source-only evidence:", work)
PY
```

The downloaded patch SHA-256 is pinned to this investigation. A changed hash
requires inspection of the upstream response before continuing. The
context-adjusted patch SHA-256 from this reproduction is
`039aa61390cc56c1b6e244d5b65f13b0ca2777a7b8dfd0e6ace47b03c3db7356`.
Passing the dry run establishes textual applicability only.

## Conftest and kernel dependencies

The proposal adds both
`is_export_symbol_present_userspace_init_fs` and
`is_export_symbol_gpl_userspace_init_fs` to `nvidia.Kbuild`.
The release's existing
[`conftest.sh`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e6a2e01579fbbd1ca2ed43fef2ee2589e9bd8bd9/kernel-open/conftest.sh#L381)
already handles both generically by reading the target kernel's
`Module.symvers`; no new conftest implementation is needed.

For Subarchy's open modules,
[`NV_CHECK_EXPORT_SYMBOL`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e6a2e01579fbbd1ca2ed43fef2ee2589e9bd8bd9/kernel-open/common/inc/nv-linux.h#L1894)
uses symbol presence. The open module declares `Dual MIT/GPL`, allowing
the GPL-only `userspace_init_fs` export. The proposal conditionally includes
`linux/fs_struct.h` and uses `scoped_with_init_fs()` for the open. This helper
temporarily swaps `current->fs` and restores it on scope exit; it does not
disable the kernel's nullfs isolation. The inline helper and GPL export are
visible in the pinned Linux
[header](https://github.com/torvalds/linux/blob/32750c77e811dba81eb92abf9182b1f424255d3a/include/linux/fs_struct.h)
and [implementation](https://github.com/torvalds/linux/blob/32750c77e811dba81eb92abf9182b1f424255d3a/fs/fs_struct.c).
On older kernels without the symbol the patch retains plain `filp_open()`.
Its additional synchronous-probe branch is conditional on
`NV_PCI_ASYNC_PROBE_SUPPORTED`, not a blanket removal of async probing.

Kvant source checks ran the **unmodified release conftest** against these
inputs. Fixture results exercise export parsing, not target kernel builds:

| `Module.symvers` input | Sanity exit | Presence macro | GPL macro |
|---|---|---|---|
| Fixture, `userspace_init_fs` exported GPL-only | 0 | 1 | 1 |
| Fixture, ordinary export | 0 | 1 | 0 |
| Fixture, another valid kernel symbol but no `userspace_init_fs` | 0 | 0 | 0 |
| Missing file | 1 | 0 | 0 |
| Local Debian `6.12.117+deb13-amd64` headers | 0 | 0 | 0 |

`compile_tests` itself exits zero even for the missing-file case. Its zero
macros are therefore insufficient evidence for an older-kernel fallback.
Never bypass `module_symvers_sanity_check`. No exact Zen 7.3.4 or LTS 6.18.63
header tree was available in this task.

For a maintainer who already has an extracted NVIDIA 620.70.06 source tree,
this read-only preflight checks each installed target header tree. It needs
neither a GPU nor root. Run from that source tree's `kernel-open` directory;
the script is the upstream `conftest.sh`, not a Subarchy replacement.

```sh
for headers in /usr/lib/modules/7.3.4-zen2-2-zen/build /usr/lib/modules/6.18.63-3-lts/build; do
    test -r "$headers/Module.symvers" || { echo "Missing headers: $headers"; exit 1; }
    sh ./conftest.sh cc x86_64 "$headers" "$headers" module_symvers_sanity_check || exit 1
    sh ./conftest.sh cc x86_64 "$headers" "$headers" compile_tests '' \
        is_export_symbol_present_userspace_init_fs is_export_symbol_gpl_userspace_init_fs || exit 1
done
```

Also inspect the target's `include/linux/fs_struct.h` for the helper. A
symbol-presence test alone does not check that macro or compile its body.
The expected Zen result is presence/GPL `1/1` with the scoped helper; the
expected LTS result is `0/0` with a valid symbol table. Those are expectations
to check on the exact headers, not results from Sputnik.

## Qualification and next action

Subarchy selects Arch's `nvidia-open-dkms`, `nvidia-utils` and both kernel
headers in `internal/hw/hw.go`; it does not maintain an open-driver package.
Its `nvidia-runtime-pm` fix in `internal/hw/fixes.go` already writes `0x02`
and `power/control=auto` rules, as documented by
[NVIDIA's 620.70.06 RTD3 guide](https://download.nvidia.com/XFree86/Linux-x86_64/620.70.06/README/dynamicpowermanagement.html).
There is no justified additional configuration fix from this evidence.

The next candidate is an upstream release or Arch package carrying the
reviewed fix. If that remains unavailable, a separate, explicitly scoped
package-qualification task can evaluate the context-only backport above.
It must produce an inspectable package rather than editing installed DKMS
sources or adding a boot-time PCI rebind service.

Before offering that candidate for Sputnik testing:

1. Record exact source, patch and package hashes. Check the actual Arch
   packaging source and patches as well as the NVIDIA release. Keep GSP
   firmware and userspace at the matching driver release, as NVIDIA's
   [build requirements](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e6a2e01579fbbd1ca2ed43fef2ee2589e9bd8bd9/README.md#how-to-build)
   require.
2. Run the conftests above and full module builds against **both exact
   kernel header trees**, with build concurrency at most two. Check generated
   macros, modpost, module version, licence and vermagic. A source dry run
   or a tiny test module does not qualify the full driver.
3. Keep signed-package and module-signing requirements intact. Preserve the
   previously working LTS kernel/module/UKI path and a package rollback before
   replacing any driver. A DKMS change can affect both kernels; retaining an
   LTS menu entry alone is insufficient rollback evidence.
4. Hand the qualified candidate and rollback evidence to the hardware owner.
   On Zen, boot through the normal path, confirm the loaded candidate and
   Intel GPU selection, close GPU clients, and unplug both AC and powered USB.
   Capture three passive readings ten seconds apart: fine-grained RTD3,
   `runtime_status=suspended`, increasing suspended time and video memory off.
   Confirm battery discharging and all external power inputs offline. Do not
   run `nvidia-smi` or another GPU monitor during idle sampling.
5. Then check an offloaded application wakes the GPU and that suspension
   returns after exit; separately check suspend/resume and the LTS control.
   Record the P9 result on #195 and [[first-install]]. A candidate pass would
   support this fix on Sputnik; direct tracing is still needed to claim the
   original open returned `-ENOENT` on that machine.

The current blocker is an exact-target, fully built and qualified driver
candidate, followed by the owner's physical battery test. PR #1512 is still
unmerged, and no such candidate was built or installed in this investigation.
A readback with AC or powered USB online does not replace that battery test.

The section below records what happened after this investigation. Steps 1
to 3 of the list above now have evidence from a disposable fixture. Steps 4
and 5 are still open.

## Candidate builds and VM boots, November 16

Copied from the dated comments on #195, all observed on Kvant on November
16, 2026 UTC. Nothing here was rerun to write this section, and nothing
was installed or loaded on Sputnik. The receipts are private files on
Kvant and are not in this repository.

**Target headers (06:55 UTC).** Both exact header trees were readable on
Sputnik. Zen `7.3.4-zen2-2-zen` has a valid `Module.symvers` with
`userspace_init_fs` exported GPL-only; LTS `6.18.63-3-lts` has a valid
table without that symbol. This fills the gap noted under
[[#Conftest and kernel dependencies]].

**Builds (07:30 UTC).** Full candidate builds passed for both kernels with
the context-only #1512 backport on NVIDIA `620.70.06`. All five modules per
kernel passed modpost, version, vermagic and BTF inspection. The Zen core
imports `userspace_init_fs`; the LTS core does not. The presence and GPL
conftest results were `1/1` on Zen and `0/0` on LTS. The private DKMS
source package SHA-256 is
`28dd80064a9d2b5ef28f18a2084b3add3dca57acf0fc2869ed41110fa7a9ec0c`; the
patch is the `039aa613…` one recorded above. Both builds emitted 11,874
objtool naked-return warnings. A control build with the unpatched
interface produced the same warnings, so the backport did not add them;
what they mean at run time is not established.

**Package transaction and reversal (08:22 UTC).** In a disposable
container, pacman replaced the stock package with the candidate and back
again for both kernels. The core srcversion went
`5B0BEF94704B2BE1D8BB68B` → `09EE8438341EA13E4C2D987` → back. The source
tree, all ten modules, both initramfs images and both UKIs returned byte
for byte to the baseline. No dependency was skipped and no hook
suppressed. A second review found no blocker. These UKIs used a synthetic
root and were not booted.

**VM boots.** The fixture is a disposable VM with an encrypted root and no
NVIDIA PCI device.

| Boot | Reported (UTC) | Result |
|---|---|---|
| Candidate, Zen `7.3.4-zen2-2-zen` | 10:31 | Passed: UEFI boot and LUKS root unlock; selected UKI, kernel, five modules and firmware checked |
| Candidate, LTS `6.18.63-3-lts` | 10:31 | Passed, same checks |
| Restored stock driver, Zen | 15:13 | Passed: UEFI boot, LUKS2 root unlock, Secure Boot enabled in the guest, no failed units |
| Restored stock driver, LTS | 15:13 | Passed, same checks |

After the restore, the core srcversion was the stock
`5B0BEF94704B2BE1D8BB68B` again, all ten saved modules matched their
recorded hashes, and the two 4,051-file source hash lists were equal.

**Memory-pressure caveat.** The first reversal did not finish. The stock
package was reinstalled and both DKMS and depmod calls returned zero, but
the Limine and initcpio post-hook was suspended for shutdown when shared
memory headroom on Kvant fell below the reserve. The EFI files generated up
to that point were not verified. A continuation at 10:30 UTC measured
2,375.7 MiB of headroom against a 2,816 MiB minimum and refused to start.
The reversal and both restored boots were completed in a later run,
reported at 15:13 UTC. The guest logged soft-lockup messages during the
pressure; they were recorded as happening at the same time, not as caused
by the driver. The final report says measurable shared-host pressure
occurred and makes no quiet-host or performance claim.

**What this does and does not show.** It shows the candidate builds for
both exact kernels, installs and uninstalls cleanly through pacman and
DKMS, and leaves both kernels able to boot and unlock an encrypted root.
Because the VM has no NVIDIA device, it shows nothing about driver
initialization, RTD3, offload or suspend. A read-only check of Sputnik
reported at 07:30 UTC found `LocalFileSigLevel=Optional`, lockdown and
module signature enforcement off, and unsigned installed NVIDIA modules,
so signing was not an extra requirement on that development install. That
was the November 14 installation; it has not been re-read since the
reinstall.

**Still open on #195 as of November 20.** Fallback custody bound to the
November 16 reinstall, which has a new encrypted root and ESP; activating
the candidate on Sputnik; the battery-only Zen test; offload wake and
return to suspend; suspend and resume; and the LTS control. On November 17
at 02:28 UTC the stock driver on core `0.0.0-638` failed P9 on Zen again
([[first-install#Results on core 638]]).

## Upstream PR #1512 has a newer head

Copied from the [#195 comment of November 20, 2026](https://github.com/subculture-collective/subarchy/issues/195#issuecomment-7033748537),
checked on Kvant at 07:51–07:53 UTC from the public GitHub API, public
source files and the private candidate directory. Nothing was built or
installed, and Sputnik was not contacted. Nothing was rerun to write this
section.

[PR #1512](https://github.com/NVIDIA/open-gpu-kernel-modules/pull/1512) is
still open and unmerged. Its head is now
[`c66b7b8abd779011b34ea6285487f0d1f5aa1f5a`](https://github.com/NVIDIA/open-gpu-kernel-modules/commit/c66b7b8abd779011b34ea6285487f0d1f5aa1f5a):
one commit, author date October 26, committer date November 17 at 17:11
UTC, and GitHub reports it mergeable and clean. Its parent is
`e6a2e01579fb`, the `620.70.06` tag. The source check and the candidate
above used the earlier head `369378dc1552ae46f7f95a598a085c0025e464b3`,
which sat on `ca2d03e6fafd` (`615.78.08`) and which GitHub reported as
conflicting on November 16. The author rebased the same commit onto
`620.70.06`.

**The candidate already carries the current fix.** The comparison found:

- The added and removed lines of the old and new heads are identical. Only
  `index` lines, hunk line numbers and three context lines differ, and
  those three are the ones the candidate's context-only correction
  replaced on November 16.
- Applying the candidate patch (`039aa613…`) and the new head's diff to
  pristine `620.70.06` gives byte-identical files: `nv-pci.c`
  `b045946dd05faa0cad310a70b48744e55a922369c94f754eaf477153a6d8e2e6` and
  `nvidia.Kbuild`
  `24499e466a7a3570be5d86291fb1418c00b77c15a2f779b3578645ed7b147898`.
  The retained candidate build trees and DKMS source hold `nv-pci.c` with
  that hash. No module was rebuilt for the comparison.
- No release carries the fix. The newest tag, `620.73.04` (published
  November 18), has the same `nv-pci.c` and `nvidia.Kbuild` as `620.70.06`.
  Arch moved to `nvidia-open-dkms 620.73.04-1` and `linux-zen 7.3.5.zen1-1`
  on November 19 without the patch. Reports by other users that
  `620.73.04` with #1512 reaches fine-grained RTD3 were read, not checked.

The comment's advice is not to rebuild now. The candidate matches the
driver and kernels in the pinned snapshot `2026/11/15`. Rebuild from the
current upstream head, against the exact new headers, only if that
snapshot advances or Sputnik's installed NVIDIA or kernel versions
otherwise stop matching the candidate; then repeat the build, transaction
and boot checks. The comparison changes none of the open items on #195
listed above.

Related: [[0006-gpu-drivers|ADR 0006]] · [[0004-kernel|ADR 0004]] · [[first-install]] · [[test-checklist]] · [[review-index]]
