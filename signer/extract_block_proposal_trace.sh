#!/bin/bash
set -euo pipefail

# Import all the helper functions
script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/../common.sh"

# Read from file if provided, else stdin
if [[ -n "${1-}" && -f "$1" ]]; then
    input_source="$1"
elif [ ! -t 0 ]; then
    input_source="/dev/stdin"
else
    echo "Usage: $0 <log_file> or pipe log data into stdin"
    exit 1
fi

# Clean up our garbage!
tmp_dir=$(mktemp -d)
trap "rm -rf $tmp_dir" EXIT

# Track all signer_signature_hash's we encounter
all_signers_file="$tmp_dir/all_signers.txt"
touch "$all_signers_file"

while IFS= read -r line; do
    timestamp=$(extract_timestamp "$line")
    [[ -z "$timestamp" ]] && continue

    # MAKE SURE YOU UPDATE THESE IF LOGGING HAS CHANGED...
    if echo "$line" | grep -q "received a block proposal"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && {
            save_time "$tmp_dir" proposal "$signer_hash" "$timestamp"
            echo "$signer_hash" >> "$all_signers_file"
        }
    elif echo "$line" | grep -q "submitting block proposal for validation"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && save_time "$tmp_dir" validation "$signer_hash" "$timestamp"
    elif echo "$line" | grep -q "Broadcasting block pre-commit to stacks node for"; then
        signer_hash=$(echo "$line" | sed -n 's/.*for \([0-9a-fA-F]\{64\}\).*/\1/p')
        [[ -n "$signer_hash" ]] && save_time "$tmp_dir" precommit "$signer_hash" "$timestamp"
    elif echo "$line" | grep -q "block response to stacks node: Accepted"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && save_time "$tmp_dir" block_accepted "$signer_hash" "$timestamp"
    elif echo "$line" | grep -q "block response to stacks node: Rejected"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && save_time "$tmp_dir" block_rejected "$signer_hash" "$timestamp"
    elif echo "$line" | grep -q "Received block acceptance and have reached"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && save_time "$tmp_dir" global_approval "$signer_hash" "$timestamp"
    elif echo "$line" | grep -q "Received block rejection and have reached"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && save_time "$tmp_dir" global_rejection "$signer_hash" "$timestamp"
    #we should treat either a block pushed or a block new event as our Push time (take the earliest of the two)
    elif echo "$line" | grep -q "Got block pushed message"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && maybe_save_earlier_time "$tmp_dir" push "$signer_hash" "$timestamp"
    elif echo "$line" | grep -q "Received a new block event"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && maybe_save_earlier_time "$tmp_dir" push "$signer_hash" "$timestamp"
    fi
done < "$input_source"

# Deduplicate signer signature hashes
sort -u "$all_signers_file" -o "$all_signers_file"

# Column headers
columns=("Signer Signature Hash" "Proposal" "Validation" "Pre-Commit" "Block Accepted" "Block Rejected" "Global Approval" "Global Rejection" "ΔProposal→Push (s)")

# Fixed widths (adjusted for readability)
widths=(64 20 20 20 20 20 20 20 20)

# Compute total table width
total_width=0
for w in "${widths[@]}"; do
    total_width=$((total_width + w))
done
total_width=$((total_width + ${#widths[@]}*3 - 1))  # account for separators " | "

# Print header
header_line=""
for i in "${!columns[@]}"; do
    header_line+=$(printf "%-${widths[i]}s" "${columns[i]}")
    [[ $i -lt $((${#columns[@]}-1)) ]] && header_line+=" | "
done
echo "$header_line"

# Print separator
printf '%*s\n' "$total_width" '' | tr ' ' '-'

# Initialize totals
total=0
count=0

# Print data rows
while IFS= read -r signer_hash; do
    prop=$(read_time "$tmp_dir" proposal "$signer_hash")
    val=$(read_time "$tmp_dir" validation "$signer_hash")
    pre=$(read_time "$tmp_dir" precommit "$signer_hash")
    acc=$(read_time "$tmp_dir" block_accepted "$signer_hash")
    rej=$(read_time "$tmp_dir" block_rejected "$signer_hash")
    glob_app=$(read_time "$tmp_dir" global_approval "$signer_hash")
    glob_rej=$(read_time "$tmp_dir" global_rejection "$signer_hash")
    push=$(read_time "$tmp_dir" push "$signer_hash")

    if [[ "$prop" != "-" && "$push" != "-" ]]; then
        delta=$(echo "$push - $prop" | bc -l)
        delta_fmt=$(printf "%.3f" "$delta")
        total=$(echo "$total + $delta_fmt" | bc -l)
        ((count++))
    else
        delta_fmt="N/A"
    fi

    printf "%-${widths[0]}s | %-${widths[1]}s | %-${widths[2]}s | %-${widths[3]}s | %-${widths[4]}s | %-${widths[5]}s | %-${widths[6]}s | %-${widths[7]}s | %-${widths[8]}s\n" \
        "$signer_hash" "$prop" "$val" "$pre" "$acc" "$rej" "$glob_app" "$glob_rej" "$delta_fmt"
done < "$all_signers_file"

# Print average
echo
if (( count > 0 )); then
    avg=$(echo "$total / $count" | bc -l)
    avg_fmt=$(printf "%.3f" "$avg")
    echo "Average ΔProposal→Push (s): $avg_fmt"
else
    echo "Average ΔProposal→Push (s): N/A (no complete proposal→push pairs)"
fi
