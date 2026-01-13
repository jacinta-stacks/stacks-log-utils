#!/usr/bin/env python3
import sys
import re
from datetime import datetime, timezone

# ----------------------------
# Config: patterns (update if logging changes)
# ----------------------------
EVENT_PATTERNS = [
    ("proposal",         "received a block proposal"),
    ("validation",       "submitting block proposal for validation"),
    ("precommit",        "Broadcasting block pre-commit to stacks node for"),
    ("block_accepted",   "block response to stacks node: Accepted"),
    ("block_rejected",   "block response to stacks node: Rejected"),
    ("global_approval",  "acceptance and have reached"),
    ("global_rejection", "rejection and have reached"),
    ("push",             "Got block pushed message"),
    ("push",             "Received a new block event"),
]

# ----------------------------
# Regex helpers
# ----------------------------
# Timestamp formats:
#   [2026-01-12 07:27:37]
#   [12345.678] (mac-style float seconds)
TS_HUMAN_RE = re.compile(r"\[(20\d{2}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]")
TS_MAC_RE   = re.compile(r"\[(\d+\.\d+)\]")

# signer_signature_hash: <64hex>   OR signer_signature_hash=<64hex>
SIGNER_HASH_RE = re.compile(r"signer_signature_hash\s*[:=]\s*([0-9a-fA-F]{64})")

# precommit line: "... for <64hex>"
PRECOMMIT_FOR_RE = re.compile(r"\bfor\s+([0-9a-fA-F]{64})\b")

def parse_timestamp(line: str):
    """
    Return timestamp as float seconds since epoch (or float seconds if mac format),
    or None if no timestamp.
    """
    m = TS_MAC_RE.search(line)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            return None

    m = TS_HUMAN_RE.search(line)
    if not m:
        return None

    ts_str = m.group(1)
    # Interpret as local time? Your log is wall-clock; use naive->epoch as local.
    # If you want strict UTC, adjust here.
    try:
        dt = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
        # Treat as local time (naive). Convert by timestamp() assuming local tz.
        return dt.timestamp()
    except Exception:
        return None

def extract_signer_hash(line: str):
    m = SIGNER_HASH_RE.search(line)
    return m.group(1) if m else None

def extract_precommit_hash(line: str):
    m = PRECOMMIT_FOR_RE.search(line)
    return m.group(1) if m else None

def set_time(times_by_event, event: str, h: str, ts: float):
    # Keep first observed time for that event/hash (matches prior behavior)
    d = times_by_event[event]
    if h not in d:
        d[h] = ts

def set_earliest_time(times_by_event, event: str, h: str, ts: float):
    # Keep earliest observed time (push event wants earliest of "new block" and "pushed")
    d = times_by_event[event]
    cur = d.get(h)
    if cur is None or ts < cur:
        d[h] = ts

def fmt_ts(ts):
    if ts is None:
        return "-"
    # Match previous output style: seconds since epoch (integer-ish)
    # Keep as integer string for readability
    return str(int(ts))

def main():
    # Input: file if provided, else stdin
    if len(sys.argv) >= 2 and sys.argv[1] != "-" :
        path = sys.argv[1]
        f = open(path, "r", errors="replace")
    else:
        f = sys.stdin

    # event -> {hash -> ts}
    times_by_event = {
        "proposal": {},
        "validation": {},
        "precommit": {},
        "block_accepted": {},
        "block_rejected": {},
        "global_approval": {},
        "global_rejection": {},
        "push": {},
    }

    seen_hashes = set()

    # Precompute substring checks (fast)
    # We’ll scan line and only do regex extraction when one of these substrings matches.
    event_substrings = EVENT_PATTERNS

    for line in f:
        ts = parse_timestamp(line)
        if ts is None:
            continue

        # Fast substring dispatch
        for event, needle in event_substrings:
            if needle in line:
                if event == "precommit":
                    h = extract_precommit_hash(line)
                else:
                    h = extract_signer_hash(line)

                if not h:
                    break

                seen_hashes.add(h)

                if event == "push":
                    set_earliest_time(times_by_event, "push", h, ts)
                else:
                    set_time(times_by_event, event, h, ts)
                break  # only one event per line expected

    if f is not sys.stdin:
        f.close()

    # Output formatting
    columns = [
        "Signer Signature Hash",
        "Proposal",
        "Validation",
        "Pre-Commit",
        "Block Accepted",
        "Block Rejected",
        "Global Approval",
        "Global Rejection",
        "ΔProposal→Push (s)",
    ]
    widths = [64, 20, 20, 20, 20, 20, 20, 20, 20]

    # Header
    header = " | ".join(f"{c:<{widths[i]}}" for i, c in enumerate(columns))
    print(header)
    total_width = sum(widths) + (len(widths) * 3 - 1)
    print("-" * total_width)

    total_delta = 0.0
    count = 0

    for h in sorted(seen_hashes):
        prop = times_by_event["proposal"].get(h)
        val  = times_by_event["validation"].get(h)
        pre  = times_by_event["precommit"].get(h)
        acc  = times_by_event["block_accepted"].get(h)
        rej  = times_by_event["block_rejected"].get(h)
        ga   = times_by_event["global_approval"].get(h)
        gr   = times_by_event["global_rejection"].get(h)
        push = times_by_event["push"].get(h)

        if prop is not None and push is not None:
            delta = push - prop
            delta_fmt = f"{delta:.3f}"
            total_delta += delta
            count += 1
        else:
            delta_fmt = "N/A"

        row = [
            h,
            fmt_ts(prop),
            fmt_ts(val),
            fmt_ts(pre),
            fmt_ts(acc),
            fmt_ts(rej),
            fmt_ts(ga),
            fmt_ts(gr),
            delta_fmt,
        ]
        print(" | ".join(f"{row[i]:<{widths[i]}}" for i in range(len(row))))

    print()
    if count > 0:
        avg = total_delta / count
        print(f"Average ΔProposal→Push (s): {avg:.3f}")
    else:
        print("Average ΔProposal→Push (s): N/A (no complete proposal→push pairs)")

if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # allow piping to head, etc.
        sys.exit(0)
