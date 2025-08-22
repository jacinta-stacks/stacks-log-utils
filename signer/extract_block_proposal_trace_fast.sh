#!/usr/bin/env bash
set -euo pipefail

# Determine this script's directory
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# MAKE SURE YOU UPDATE THESE IF LOGGING HAS CHANGED...
patterns="received a block proposal|submitting block proposal for validation|Broadcasting block pre-commit to stacks node for|block response to stacks node:|Received block acceptance and have reached|Received block rejection and have reached|Got block pushed message|Received a new block event"

# Read from file if provided, else stdin
if [[ $# -ge 1 && -f "$1" ]]; then
    grep -E "$patterns" "$1" | "$script_dir/extract_block_proposal_trace.sh"
elif [ ! -t 0 ]; then
    grep -E "$patterns" | "$script_dir/extract_block_proposal_trace.sh"
else
    echo "Usage: $0 <log_file> or pipe log data into stdin"
    exit 1
fi
