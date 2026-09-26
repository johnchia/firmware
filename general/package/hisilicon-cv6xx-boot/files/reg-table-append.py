#!/usr/bin/env python3
"""Append a camera's register records to a CV6xx boot reg table.

The boot ROM applies the reg table (image_tool's boot_param_file0) before the
GSL runs, so it is the earliest thing on the board that can park a pad. A
camera may need that: the H4's vendor bootloader parks the enable and the
bus of an IR-cut driver chip its firmware never uses, and the reference
DDR table this package ships leaves those pads on their Ethernet-LED and
I2C functions instead.

usage: reg-table-append.py BASE.bin OUT.bin [RECORDS.txt]

RECORDS.txt holds one record per line: ADDR VALUE [DELAY [ATTR]], hex or
decimal, '#' to end of line ignored. DELAY and ATTR default to the plain
write the vendor tables use (0 and 0xfd). With no RECORDS.txt the base
table is copied unchanged.

Table format, from the vendor's reginfo/*.bin: a 0x1c8-byte header (magic,
"V0.1", the date and the spreadsheet the table was exported from), then
16-byte records {addr, value, delay, attr} ending with an all-zero record.
image_tool copies the file into a 0x3000-byte slot.
"""
import struct
import sys

MAGIC = b"\x2b\x8c\x6e\x1a\x1a\x6e\x8c\x2b"
HEADER = 0x1C8
SLOT = 0x3000
REC = 16
DEFAULT_DELAY = 0
DEFAULT_ATTR = 0xFD


def die(msg):
    sys.stderr.write("reg-table-append: %s\n" % msg)
    sys.exit(1)


def parse_records(path):
    out = []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            fields = line.split()
            if len(fields) < 2 or len(fields) > 4:
                die("%s:%d: want ADDR VALUE [DELAY [ATTR]]" % (path, n))
            try:
                vals = [int(x, 0) for x in fields]
            except ValueError:
                die("%s:%d: not a number: %s" % (path, n, line))
            vals += [DEFAULT_DELAY, DEFAULT_ATTR][len(vals) - 2:]
            addr, value, delay, attr = vals
            if addr == 0 or addr & 3:
                die("%s:%d: %#x is not a register address" % (path, n, addr))
            for v in vals:
                if not 0 <= v <= 0xFFFFFFFF:
                    die("%s:%d: value out of range: %s" % (path, n, line))
            out.append((addr, value, delay, attr))
    return out


def main(argv):
    if len(argv) not in (3, 4):
        die("usage: reg-table-append.py BASE.bin OUT.bin [RECORDS.txt]")
    base, out = argv[1], argv[2]
    data = open(base, "rb").read()
    if data[: len(MAGIC)] != MAGIC:
        die("%s: not a reg table (bad magic)" % base)
    if len(data) < HEADER + REC:
        die("%s: too short" % base)
    records = []
    off = HEADER
    while off + REC <= len(data):
        rec = struct.unpack_from("<4I", data, off)
        off += REC
        if rec == (0, 0, 0, 0):
            break
        records.append(rec)
    else:
        die("%s: no terminating record" % base)
    if not records or records[0][0] >> 28 not in (0x1, 0x2):
        die("%s: first record %#x does not look like a register" % (base, records[0][0] if records else 0))
    if any(b for b in data[off:]):
        die("%s: data after the terminating record" % base)

    extra = parse_records(argv[3]) if len(argv) == 4 else []
    total = HEADER + (len(records) + len(extra) + 1) * REC
    if total > SLOT:
        die("%d records do not fit the %#x-byte slot" % (len(records) + len(extra), SLOT))

    with open(out, "wb") as f:
        f.write(data[:HEADER])
        for rec in records + extra:
            f.write(struct.pack("<4I", *rec))
        f.write(b"\0" * REC)
    for addr, value, delay, attr in extra:
        print("reg-table-append: %#010x = %#010x (delay %d, attr %#x)" % (addr, value, delay, attr))
    print("reg-table-append: %d base + %d camera records" % (len(records), len(extra)))


if __name__ == "__main__":
    main(sys.argv)
