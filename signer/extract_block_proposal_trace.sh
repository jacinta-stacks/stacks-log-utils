#!/usr/bin/env python3
import sys
import re
from datetime import datetime

# ----------------------------
# Config: patterns (update if logging changes)
# ----------------------------
EVENT_PATTERNS = [
    ("proposal",         "received a block proposal"),
    ("validation",       "submitting block proposal for validation"),
    ("precommit",        "Broadcasting block pre-commit to stacks node for"),
    ("block_accepted",   "block response to stacks node: Accepted"),
    ("block_rejected",   "block response to stacks node: Rejected"),
    ("global_approval",  "Received block acceptance and have reached"),
    ("global_rejection", "Received block rejection and have reached"),
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

def set_first(d, h, ts):
    """Set first observed timestamp only."""
    if h not in d:
        d[h] = ts

def set_earliest(d, h, ts):
    """Keep earliest timestamp."""
    cur = d.get(h)
    if cur is None or ts < cur:
        d[h] = ts

def fmt_ts(ts):
    return "-" if ts is None else str(int(ts))

def main():
    # Input: file if provided, else stdin
    if len(sys.argv) >= 2 and sys.argv[1] != "-":
        f = open(sys.argv[1], "r", errors="replace")
    else:
        f = sys.stdin

    # event -> {hash -> ts}
    times = {
        "proposal": {},
        "validation": {},
        "precommit": {},
        "block_accepted": {},
        "block_rejected": {},
        "global_approval": {},
        "global_rejection": {},
        "push": {},
    }

    seen = set()

    for line in f:
        ts = parse_timestamp(line)
        if ts is None:
            continue

        # Allow multiple events per line (no early break)
        for event, needle in EVENT_PATTERNS:
            if needle not in line:
                continue

            if event == "precommit":
                h = extract_precommit_hash(line)
            else:
                h = extract_signer_hash(line)

            if not h:
                continue

            seen.add(h)

            if event == "push":
                # Push time = earliest of pushed/new-block events
                set_earliest(times["push"], h, ts)

                # Global Approval time should also be populated by push lines.
                # Take the earliest between actual global-approval threshold and push visibility.
                set_earliest(times["global_approval"], h, ts)

            elif event == "global_approval":
                # Global Approval = earliest (not first), because we might see multiple.
                set_earliest(times["global_approval"], h, ts)

            else:
                # All other events: first time observed is good enough
                set_first(times[event], h, ts)

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
        "Push",
        "ΔProposal→Push (s)",
    ]
    widths = [64, 20, 20, 20, 20, 20, 20, 20, 20, 20]

    header = " | ".join(f"{c:<{widths[i]}}" for i, c in enumerate(columns))
    print(header)
    total_width = sum(widths) + (len(widths) * 3 - 1)
    print("-" * total_width)

    total_delta = 0.0
    count = 0

    for h in sorted(seen):
        prop = times["proposal"].get(h)
        val  = times["validation"].get(h)
        pre  = times["precommit"].get(h)
        acc  = times["block_accepted"].get(h)
        rej  = times["block_rejected"].get(h)
        ga   = times["global_approval"].get(h)
        gr   = times["global_rejection"].get(h)
        push = times["push"].get(h)

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
            fmt_ts(push),
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
