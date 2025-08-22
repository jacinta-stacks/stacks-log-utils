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

assembled_file="$tmp_dir/assembled.csv"
validation_file="$tmp_dir/validation.csv"
accepted_file="$tmp_dir/accepted.csv"
broadcasted_file="$tmp_dir/broadcasted.csv"

while IFS= read -r line; do
    timestamp=$(extract_timestamp "$line")
    [[ -z "$timestamp" ]] && continue
    # MAKE SURE YOU UPDATE THESE IF LOGGING HAS CHANGED...
    if echo "$line" | grep -q "Miner: Assembled block #"; then
        block_num=$(echo "$line" | grep -oE 'Assembled block #[0-9]+' | grep -oE '[0-9]+')
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$block_num" && -n "$signer_hash" ]] && echo "${block_num}|${signer_hash}|${timestamp}" >> "$assembled_file"
        continue
    elif echo "$line" | grep -q "Received block proposal request"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && echo "${signer_hash}|${timestamp}" >> "$validation_file"
        continue
    elif echo "$line" | grep -q "Received enough signatures, block accepted"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && echo "${signer_hash}|${timestamp}" >> "$accepted_file"
        continue
    elif echo "$line" | grep -q "Miner: Block signed by signer set and broadcasted"; then
        signer_hash=$(extract_signer_signature_hash "$line")
        [[ -n "$signer_hash" ]] && echo "${signer_hash}|${timestamp}" >> "$broadcasted_file"
        continue
    fi
done < "$input_source"

# Column headers
columns=("Signer Signature Hash" "Assembled" "Validation" "Block Accepted" "Broadcasted" "ΔAssembled→Broadcasted")
widths=(64 12 12 16 14 22)

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
printf '%*s\n' "$total_width" '' | tr ' ' '-'

# Initialize totals
total_delta=0
delta_count=0

sorted_assembled="$tmp_dir/sorted_assembled.csv"
sort -t '|' -k1,1n "$assembled_file" > "$sorted_assembled"

# Print data rows
while IFS='|' read -r block_num signer_hash assembled_ts; do
    val_ts=$(get_earliest_ts "$validation_file" "$signer_hash")
    acc_ts=$(get_earliest_ts "$accepted_file" "$signer_hash")
    broad_ts=$(get_earliest_ts "$broadcasted_file" "$signer_hash")

    if [[ "$broad_ts" != "-" && "$assembled_ts" != "-" ]]; then
        delta=$(echo "$broad_ts - $assembled_ts" | bc)
        total_delta=$(echo "$total_delta + $delta" | bc)
        delta_fmt="$delta"
        delta_count=$((delta_count + 1))
    else
        delta_fmt="-"
    fi

    printf "%-${widths[0]}s | %-${widths[1]}s | %-${widths[2]}s | %-${widths[3]}s | %-${widths[4]}s | %-${widths[5]}s\n" \
        "$signer_hash" "${assembled_ts:-"-"}" "${val_ts:-"-"}" "${acc_ts:-"-"}" "${broad_ts:-"-"}" "$delta_fmt"
done < "$sorted_assembled"

# Print average
echo
if (( delta_count > 0 )); then
    avg_delta=$(echo "scale=3; $total_delta / $delta_count" | bc)
    printf "Total Average ΔAssembled→Broadcasted: %s seconds (from %d records)\n" "$avg_delta" "$delta_count"
else
    echo "No valid ΔAssembled→Broadcasted entries to calculate average."
fi

