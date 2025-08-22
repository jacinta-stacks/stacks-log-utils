# Stacks Log Utilities

This repository contains Bash scripts for extracting and analyzing key events from **Stacks miner** and **Stacks signer** logs. The tools help parse logs, track proposals, validations, block assemblies, broadcasts, approvals, and pushes, and compute timing between them.

⚠️ WARNING: Fragile Scripts ⚠️

Important: These scripts are extremely fragile and should be used with caution.
They rely on grepping log files for very specific patterns and exact formatting.
Any change in the log message text, timestamp format (see below for expected timestamp format), or spacing can break the scripts or produce incorrect results.
Always verify output manually before relying on it for any decisions or automation.
Use at your own risk! 🚨

---

The scripts handle two timestamp formats:

Numeric / Mac-style timestamp (epoch with fractional seconds. This is preferred as it gives more accurate timing).
- Example: 1752263685.497974
- Format: [seconds_since_epoch.fraction]
- Extracted with extract_timestamp_mac() using a regex like \[([0-9]+\.[0-9]+)\].

Human-readable timestamp (Avoid this format for improved accuracy)
- Example: [2025-08-21 14:23:11]
- Format: [YYYY-MM-DD HH:MM:SS]
- Converted to seconds since epoch using date (on macOS, date -j -f "%Y-%m-%d %H:%M:%S").

## Miner Log Utilities

### Scripts

#### 1. `/miner/extract_block_assembled_trace.sh`

**Purpose:**  
Parses a info level Stacks miner log and outputs a table showing key events per block signer signature hash and the timing between block assembly and broadcast.

**Usage:**

```bash
sh ./signer/extract_block_assembled_trace.sh <log_file>
```

**Output:**  

A formatted table with the following columns:

| Column                  | Description                                               |
|-------------------------|-----------------------------------------------------------|
| Signer Signature Hash   | Signer signature hash of an assembled block               |
| Assembled               | Timestamp when the block was assembled                    |
| Validation              | Timestamp when a block proposal request was received     |
| Block Accepted          | Timestamp when enough signatures were received to accept the block |
| Broadcasted             | Timestamp when the block was broadcasted                 |
| ΔAssembled→Broadcasted  | Time difference in seconds from block assembly to broadcast |

**Notes:**
-   This script expects at least WARN level logs to operate correctly.

#### 2. /miner/extract_block_assembled_trace_fast.sh

Purpose:
Pre-filters a large Stacks miner log to include only relevant events, then pipes it into `extract_block_assembled_trace.sh` for parsing. This significantly improves processing speed for large log files.

**Usage:**

```bash
sh ./extract_block_assembled_trace_fast.sh <log_file>
```

**Output:**  
Same as `/miner/extract_block_assembled_trace.sh`

**Notes:**
-   This script expects at least WARN level logs to operate correctly.

---

## Stacks Signer Log Utilities

This folder contains Bash scripts for extracting and analyzing relevant events from **Stacks signer logs**. 

---

### Scripts

#### 1. `signer/extract_block_proposal_trace.sh`

**Purpose:**  
Parses a pre-filtered Stacks signer log and outputs a table showing key events per signer signature hash and the timing between proposal submission and push.

**Usage:**

```bash
./extract_block_proposal_trace.sh <log_file>
```

**Output:**
A formatted table with the following columns:

| Column                  | Description                                                  |
|-------------------------|--------------------------------------------------------------|
| Signer Signature Hash   | Signer signature hash of a block proposal                    |
| Proposal                | Timestamp when a block proposal was received                 |
| Validation              | Timestamp when a block proposal was submitted for validation |
| Pre-Commit              | Timestamp when the block pre-commit was broadcasted          |
| Block Accepted          | Timestamp when the block accept response was broadcasted     |
| Block Rejected          | Timestamp when the block reject response was broadcasted     |
| Global Approval         | Timestamp when global block acceptance was reached           |
| Global Rejection        | Timestamp when global block rejection was reached            |
| Push                    | Earliest timestamp of block push events                      |
| ΔProposal→Push s        | Time difference in seconds from proposal to push             |

**Notes:**
-   This script expects at least DEBUG level logs to operate correctly.

#### 2. /signer/extract_block_proposal_trace_fast.sh

Purpose:
Pre-filters a large Stacks signer log to include only relevant events, then pipes it into `extract_block_proposal_trace.sh` for parsing. This significantly improves processing speed for large log files.

**Usage:**

```bash
sh ./extract_block_proposal_trace_fast.sh <log_file>
```

**Output:**  

Same as `/miner/extract_block_proposal_trace.sh`

**Notes:**
-   This script expects at least DEBUG level logs to operate correctly.

## Notes

- All scripts require **Bash** and standard Unix utilities (`grep`, `sed`, `awk`, `bc`).  
- `extract_block_assembled_trace.sh` and `extract_block_proposal_trace.sh` and can be used standalone but they are inefficiently written and expect either smaller log files or pre-filtered input.
- `extract_block_assembled_trace_fast.sh` and `extract_block_proposal_trace_fast.sh` are recommended over the underlying bash scripts to speed up processing.
- Tested on **macOS** and **Linux** environments.
