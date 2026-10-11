#!/bin/sh
# One-shot PC-side check of the GitGet diagnostic package.
# Covers: syntax and portability, line endings, a sandboxed run that proves the
# report is produced and the package folder is not modified, report sections,
# a sensitive-data pattern check, and ZIP build, permissions, manifest and
# checksum. It cannot prove anything about the physical R36S.
# Usage: sh tests/check_diagnostic.sh   (prints PASS or the list of failures)

HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC="$HERE/src/diagnostic"
SCRIPT="$SRC/ports/GitGet Diagnostic.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gitget-check.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT
fail=0
bad() { printf 'FAIL: %s\n' "$1"; fail=1; }

# 1. Syntax and portability
sh -n "$SCRIPT" || bad "sh -n reports a syntax error"
if command -v dash >/dev/null 2>&1; then
  dash -n "$SCRIPT" || bad "dash -n reports a syntax error"
fi
if grep -n -E '\[\[[^:]|<<<|&>|echo -e|^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*=\(|^[[:space:]]*(local|source|function) ' "$SCRIPT" >"$TMP/bashisms.txt"; then
  bad "possible bash-only syntax: $(head -n 3 "$TMP/bashisms.txt" | tr '\n' ' ')"
fi
head -n 1 "$SCRIPT" | grep -q '^#!/bin/sh$' || bad "launcher must start with #!/bin/sh"

# 2. Unix line endings in every packaged text file
cr=$(printf '\r')
for f in "$SRC"/ports/*.sh "$SRC"/ports/gitget-diag/*.txt; do
  if grep -q "$cr" "$f"; then bad "CRLF line endings in $f"; fi
done

# 3. Sandboxed run: report is produced, nothing else is touched
cp -R "$SRC/ports" "$TMP/ports"
mkdir "$TMP/out" "$TMP/home"
before=$(cd "$TMP/ports" && find . | sort | cksum)
GITGET_DIAG_NO_SCREEN=1 GITGET_DIAG_NO_WAIT=1 GITGET_DIAG_OUT_DIR="$TMP/out" HOME="$TMP/home" \
  sh "$TMP/ports/GitGet Diagnostic.sh" >"$TMP/run.log" 2>&1 || bad "script exit status is not 0"
after=$(cd "$TMP/ports" && find . | sort | cksum)
[ "$before" = "$after" ] || bad "script changed its own package folder"
report="$TMP/out/GitGet_Device_Report.txt"
if [ ! -s "$report" ]; then
  bad "report file missing or empty"
else
  [ "$(ls -A "$TMP/out")" = "GitGet_Device_Report.txt" ] || bad "temporary files left behind: $(ls -A "$TMP/out" | tr '\n' ' ')"
  for s in "KEY FINDINGS" "1. REPORT INFO" "2. OS AND KERNEL" "3. BOARD AND DEVICE TREE" \
           "4. CPU AND ARCHITECTURE" "5. MEMORY AND LIMITS" "6. STORAGE AND WRITABLE LOCATIONS" \
           "7. DISPLAY AND GPU" "8. INPUT DEVICES" "9. AUDIO AND POWER" \
           "10. COMMAND-LINE TOOLS AND RUNTIMES" "11. LIBRARIES" "12. LIBRARIES USED BY SYSTEM PROGRAMS" \
           "13. PORTMASTER AND PORTS LAYOUT" "14. NETWORK, TLS AND CLOCK" "15. PROCESSES AND ENVIRONMENT" \
           "END OF REPORT"; do
    grep -q -F "$s" "$report" || bad "report section missing: $s"
  done
  lines=$(wc -l < "$report" | tr -d ' ')
  [ "$lines" -lt 3000 ] || bad "report is unexpectedly long ($lines lines)"
  if grep -i -E '^serial|psk=|password=[^R]|ssid=' "$report" >/dev/null; then
    bad "report contains a sensitive-looking line"
  fi
fi

# 4. ZIP build, layout, permissions, manifest, checksum
python3 -I "$HERE/tools/build_diagnostic.py" --out "$TMP/dist" >"$TMP/build.log" 2>&1 || bad "ZIP build failed: $(tail -n 2 "$TMP/build.log" | tr '\n' ' ')"
zipfile=$(ls "$TMP"/dist/GitGet-Diagnostic-*.zip 2>/dev/null | head -n 1)
if [ -z "$zipfile" ]; then
  bad "no ZIP produced"
else
  (cd "$TMP/dist" && sha256sum -c ./*.sha256 >/dev/null 2>&1) || bad "ZIP checksum file does not match"
  python3 -I - "$zipfile" "$SCRIPT" <<'PY' || bad "ZIP content check failed"
import hashlib, sys, zipfile
zpath, script = sys.argv[1], sys.argv[2]
expected = {"ports/GitGet Diagnostic.sh", "ports/gitget-diag/README.txt", "ports/gitget-diag/MANIFEST.txt"}
with zipfile.ZipFile(zpath) as z:
    names = set(z.namelist())
    assert names == expected, f"unexpected listing: {sorted(names)}"
    assert z.testzip() is None, "corrupt member"
    info = z.getinfo("ports/GitGet Diagnostic.sh")
    assert (info.external_attr >> 16) & 0o111, "launcher is not marked executable"
    assert z.read("ports/GitGet Diagnostic.sh") == open(script, "rb").read(), "launcher differs from source"
    manifest = z.read("ports/gitget-diag/MANIFEST.txt").decode().splitlines()
    listed = {}
    for line in manifest[2:]:
        digest, size, path = line.split("  ", 2)
        listed[path] = (digest, int(size))
    for name in expected - {"ports/gitget-diag/MANIFEST.txt"}:
        data = z.read(name)
        assert listed[name] == (hashlib.sha256(data).hexdigest(), len(data)), f"manifest mismatch: {name}"
PY
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: syntax, line endings, sandbox run, report sections, privacy patterns, ZIP layout, manifest and checksum"
fi
exit "$fail"
