#!/bin/sh
# Regression test for load_hisilicon's os_mem_size derivation.
#
# Catches #2059: kernel cmdline mem=NM was unconditionally accepted as the
# OS/MMZ split, which broke V4+CMA boards where bootargs pass mem=<totalmem>
# (with the MMZ chunk CMA-reserved within it). Result: os_mem_size=mem_total,
# the existing "[ os_mem >= total ]" guard tripped, script exited before any
# insmod, every camera came up with empty lsmod.
#
# Two-part check:
#   Part 1 — logic test: synthetic harness reproducing the post-fix code.
#            Exercises the parsing rules directly; independent of script files.
#   Part 2 — drift test: every general/package/hisilicon-osdrv-*/.../load_hisilicon
#            must contain the validation block. If someone reverts the fix in any
#            family the drift test fails immediately.
#
# Lightweight: pure shell, no QEMU, runs in a few seconds.

set -eu

fail=0
ok()   { echo "ok   $*"; }
bad()  { echo "FAIL $*"; fail=$((fail + 1)); }
T()    { local exp="$1" act="$2" desc="$3"
         if [ "$exp" = "$act" ]; then ok "$desc"; else bad "$desc -- want '$exp', got '$act'"; fi; }

# ----- Part 1: parsing logic -----
# Mirrors the post-fix block in every load_hisilicon. Any divergence here
# (vs the scripts) is caught by Part 2.
parse_os_mem() {
    cmdline="$1"; mem_total="$2"; osmem_env="$3"
    os_mem_size=$(printf '%s' "$cmdline" | awk 'BEGIN{RS=" "} /^mem=[0-9]+M/{gsub(/^mem=|M.*$/,""); print; exit}')
    if [ -n "$os_mem_size" ] && [ "$os_mem_size" -ge "$mem_total" ]; then
        os_mem_size=""
    fi
    if [ -z "$os_mem_size" ]; then
        os_mem_size="$osmem_env"
    fi
    : "${os_mem_size:=32}"
    printf '%s\n' "$os_mem_size"
}

echo "=== Part 1: os_mem_size derivation logic ==="
# The bug case: V4+CMA cmdline passes mem=<totalmem>. Pre-fix this set
# os_mem_size=128, mem_total=128, then the load_hisilicon guard "[ os_mem
# >= total ]" exited the whole script. Post-fix the validation block
# discards the cmdline value and falls through to the osmem env (32).
T 32 "$(parse_os_mem 'mem=128M mmz_allocator=cma mmz=anonymous,0,0x42000000,96M' 128 32)" \
   "V4+CMA mem=128M, totalmem=128M → fall through to osmem env (#2059)"

# Legacy split: cmdline mem= is strictly less than totalmem, signaling
# a real OS/MMZ split. Use the cmdline value as authoritative.
T 96 "$(parse_os_mem 'mem=96M mmz_allocator=hisi mmz=anonymous,0,0x46000000,32M' 128 32)" \
   "legacy mem=96M, totalmem=128M → use cmdline 96 (PR #2039 intent)"

# No mem= at all — fall back to env.
T 32 "$(parse_os_mem 'console=ttyAMA0,115200 root=/dev/mtdblock3' 64 32)" \
   "no cmdline mem= → fall back to osmem env"

# Neither cmdline nor env — script default of 32.
T 32 "$(parse_os_mem '' 64 '')" \
   "no cmdline mem=, no env → default 32"

# Misconfigured cmdline (mem= over total). Still fall through to env to
# avoid the >= guard later in the script killing the boot.
T 64 "$(parse_os_mem 'mem=256M' 128 64)" \
   "mem=256M > totalmem=128 → fall through (avoid guard)"

# Edge: mem= equals totalmem-1 (legitimate split with 1M for MMZ — silly
# but valid). Should still use cmdline.
T 127 "$(parse_os_mem 'mem=127M' 128 32)" \
   "mem=127M, totalmem=128M → use cmdline 127"

# ----- Part 2: every hisilicon-osdrv-* script contains the validation -----
echo
echo "=== Part 2: validation block present in every load_hisilicon ==="
needle='if \[ -n "\$os_mem_size" \] && \[ "\$os_mem_size" -ge "\$mem_total" \]; then'
scripts=$(find general/package -name 'load_hisilicon' -path '*hisilicon-osdrv-*' | sort)

if [ -z "$scripts" ]; then
    bad "no hisilicon-osdrv-*/files/script/load_hisilicon found — repo layout changed?"
else
    count=$(printf '%s\n' "$scripts" | wc -l)
    echo "scanning $count load_hisilicon copies"
    for s in $scripts; do
        family=$(printf '%s\n' "$s" | sed 's|.*hisilicon-osdrv-||; s|/.*||')
        if grep -qE "$needle" "$s"; then
            ok "$family: validation block present"
        else
            bad "$family: validation block MISSING — fix from #2060 was reverted or not applied"
        fi
    done
fi

# ----- Part 3: the K/M/G parser (hi3516cv6xx only, so far) -----
#
# A board that keeps its vendor U-Boot has an environment this tree does not
# write. The CV608's OEM passes mem=41776K, which the M-only pattern in Part 1
# does not match; os_mem_size then falls through to a literal 32 and the MMZ is
# placed 8.8 MiB inside the kernel's own RAM, with nothing logged.
#
# The replacement must be a STRICT SUPERSET: every cmdline the old pattern
# matched has to yield the same number, or this becomes a flag day for boards
# that are working today. Part 3a asserts exactly that, case by case.
echo
echo "=== Part 3: K/M/G parser is a superset of the M-only one ==="

parse_legacy() {
    printf '%s' "$1" | awk 'BEGIN{RS=" "} /^mem=[0-9]+M/{gsub(/^mem=|M.*$/,""); print; exit}'
}
parse_kmg() {
    printf '%s' "$1" | awk 'BEGIN{RS=" "} /^mem=[0-9]+[KMG]/{
        n=$0; sub(/^mem=/,"",n); u=n; sub(/^[0-9]+/,"",u); u=substr(u,1,1); n=n+0
        if (u=="K") n=int((n+1023)/1024); else if (u=="G") n*=1024
        print n; exit}'
}

# 3a: agreement on every form the old pattern accepted, plus the no-mem case.
for c in \
    'mem=32M mmz_allocator=ot console=ttyAMA0,115200' \
    'mem=128M mmz_allocator=cma mmz=anonymous,0,0x42000000,96M' \
    'mem=96M mmz_allocator=hisi mmz=anonymous,0,0x46000000,32M' \
    'mem=256M' \
    'mem=127M' \
    'mem=64M@0x40000000 console=ttyS0' \
    'mem=32MB console=ttyS0' \
    'console=ttyAMA0,115200 root=/dev/mtdblock3'
do
    T "$(parse_legacy "$c")" "$(parse_kmg "$c")" "superset: $c"
done

# 3b: the forms the old pattern silently dropped.
T 41   "$(parse_kmg 'mem=41776K console=ttyAMA0,115200')" \
   "mem=41776K -> 41 (rounded UP; 40 would overlap by the fraction)"
T 40   "$(parse_kmg 'mem=40960K')" \
   "mem=40960K -> 40 (exact MiB, no rounding)"
T 1024 "$(parse_kmg 'mem=1G console=ttyS0')" \
   "mem=1G -> 1024"

# ----- Part 4: the overlap guard -----
#
# mmz_start is arithmetic over values that may be defaults, and the modprobe's
# `|| report_error` catches a failed insert, not a successful insert of a zone
# that overlaps the kernel. The guard compares against /proc/iomem instead.
echo
echo "=== Part 4: MMZ overlap guard ==="

overlaps() {  # mmz_start, System RAM end (inclusive, as /proc/iomem prints it)
    ram_end="$2"
    if [ -n "$ram_end" ] && [ $(($1)) -le $((0x$ram_end)) ]; then echo yes; else echo no; fi
}
T yes "$(overlaps 0x42000000 428cbfff)" "the CV608 bug: MMZ 0x42000000 under RAM ending 0x428cbfff"
T no  "$(overlaps 0x42900000 428cbfff)" "parser-fixed CV608: 0x42900000 clears it"
T no  "$(overlaps 0x42000000 41ffffff)" "mem=32M split: zone starts exactly one byte past RAM"
T no  "$(overlaps 0x42000000 '')"       "unreadable /proc/iomem does not fabricate an error"

# ----- Part 5: SENSOR reaches the modules -----
#
# SENSOR (environment or probe) and SNS_TYPE0 (what open_sys_config binds VI and
# the MIPI lanes for) name the same part. The -sensor0 arm seeds SENSOR from
# SNS_TYPE0; the reverse direction was missing, so a board whose environment
# said os04d10 still configured the family default sc4336p.
#
# "Usable" is two conditions: open_sys_config must know the name, and unless it
# is a parallel input the libsns_*.so must be on the image. A target trimmed to
# one board's sensor can have a compiled-in default naming a driver it no longer
# ships, which is the case the second condition exists for.
echo
echo "=== Part 5: SENSOR seeds SNS_TYPE0 ==="

SNS_SUPPORTED="sc4336p gc4023 sc450ai sc500ai sc431hai os04d10 imx307 os02m10 bt1120 bt656 bt601"
sns_dir=$(mktemp -d)
: > "$sns_dir/libsns_os04d10.so"
: > "$sns_dir/libsns_imx307.so"

sns_usable() {  # mirrors the script; $sns_dir stands in for /usr/lib/sensors
    [ -n "$1" ] || return 1
    case " $SNS_SUPPORTED " in *" $1 "*) ;; *) return 1 ;; esac
    case "$1" in bt*) return 0 ;; esac
    [ -e "$sns_dir/libsns_$1.so" ]
}
usable() { if sns_usable "$1"; then echo yes; else echo no; fi; }

T yes "$(usable os04d10)" "a sensor this image ships is usable"
T no  "$(usable sc4336p)" "open_sys_config knows sc4336p but the driver is not shipped"
T no  "$(usable imx335)"  "a name the driver set does not carry is never usable"
T yes "$(usable bt1120)"  "parallel inputs are usable with no libsns at all"
T no  "$(usable '')"      "an unset SENSOR is not usable"

seed_sns() {  # SENSOR, starting SNS_TYPE0, probe answer -> SNS_TYPE0 for modprobe
    SENSOR="$1"; SNS_TYPE0="$2"; probe="$3"
    if ! sns_usable "$SENSOR"; then
        sns_usable "$probe" && SENSOR="$probe"
    fi
    if sns_usable "$SENSOR" && [ "$SENSOR" != "$SNS_TYPE0" ]; then SNS_TYPE0=$SENSOR; fi
    echo "$SNS_TYPE0"
}
T os04d10 "$(seed_sns os04d10 sc4336p '')"        "the CV608 bug: sensor=os04d10 now reaches sns0"
T imx307  "$(seed_sns '' sc4336p imx307)"         "no SENSOR: the probe supplies one"
T imx307  "$(seed_sns sc4336p sc4336p imx307)"    "SENSOR names a driver we dropped: the probe wins"
T sc4336p "$(seed_sns sc4336p sc4336p '')"        "...and with no probe answer, the default is left alone"
T sc4336p "$(seed_sns imx335 sc4336p imx999)"     "neither SENSOR nor probe usable: nothing reaches modprobe"
T os04d10 "$(seed_sns os04d10 os04d10 '')"        "-sensor0 already agreed; nothing to do"
rm -rf "$sns_dir"

# ----- Part 6: the fix is present where it is claimed to be -----
echo
echo "=== Part 6: cv6xx carries the fixes ==="
cv6xx=general/package/hisilicon-osdrv-hi3516cv6xx/files/script/load_hisilicon
if [ ! -f "$cv6xx" ]; then
    bad "hi3516cv6xx load_hisilicon missing -- repo layout changed?"
else
    grep -q 'mem=\[0-9\]+\[KMG\]' "$cv6xx" \
        && ok "hi3516cv6xx: K/M/G parser present" \
        || bad "hi3516cv6xx: K/M/G parser MISSING -- a vendor-env board silently mis-places the MMZ"
    grep -q 'overlaps System RAM' "$cv6xx" \
        && ok "hi3516cv6xx: MMZ overlap guard present" \
        || bad "hi3516cv6xx: MMZ overlap guard MISSING"
    grep -q 'SNS_TYPE0=$SENSOR' "$cv6xx" \
        && ok "hi3516cv6xx: SENSOR seeds SNS_TYPE0" \
        || bad "hi3516cv6xx: SENSOR->SNS_TYPE0 seed MISSING -- every board configures the default sensor"
    grep -q 'libsns_$1.so' "$cv6xx" \
        && ok "hi3516cv6xx: usability checks the driver is shipped" \
        || bad "hi3516cv6xx: sns_usable does not check libsns_*.so -- a trimmed image can select a driver it lacks"
    grep -q 'ipcinfo --short-sensor' "$cv6xx" \
        && ok "hi3516cv6xx: falls back to the bus probe" \
        || bad "hi3516cv6xx: no probe fallback -- an unusable SENSOR lands on a literal default"
    # The list is validated against, and printed by usage(). Two copies drift.
    grep -q 'Available sensors:$SNS_SUPPORTED' "$cv6xx" \
        && ok "hi3516cv6xx: usage prints the list it validates against" \
        || bad "hi3516cv6xx: usage has its own sensor list -- it will drift from SNS_SUPPORTED"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "All load_hisilicon regression checks passed."
    exit 0
else
    echo "$fail check(s) failed. See https://github.com/OpenIPC/firmware/issues/2059"
    exit 1
fi
