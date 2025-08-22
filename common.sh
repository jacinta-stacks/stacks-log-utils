#!/bin/bash
set -euo pipefail

extract_timestamp_mac() {
    local line="$1"
    echo "$line" | sed -E 's/.*\[([0-9]+\.[0-9]+)\].*/\1/' | grep -E '^[0-9]+\.[0-9]+$'
}

extract_timestamp_human() {
    local line="$1"
    local ts
    ts=$(echo "$line" | sed -E 's/.*\[(20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\].*/\1/')
    if [[ -n "$ts" ]]; then
        # macOS date format
        date -j -f "%Y-%m-%d %H:%M:%S" "$ts" +"%s" 2>/dev/null || true
    fi
}

extract_timestamp() {
    local line="$1"
    local ts
    ts=$(extract_timestamp_mac "$line")
    if [[ -n "$ts" ]]; then
        echo "$ts"
        return
    fi
    ts=$(extract_timestamp_human "$line")
    if [[ -n "$ts" ]]; then
        echo "$ts"
    fi
}

extract_signer_signature_hash() {
    local line="$1"
    echo "$line" | sed -n 's/.*signer_signature_hash: \([0-9a-fA-F]\{64\}\).*/\1/p'
}

# Store a timestamp to temp storage
save_time() {
    local tmp_dir=$1
    local event=$2
    local hash=$3
    local timestamp=$4
    echo "$timestamp" > "$tmp_dir/${event}_${hash}"
}

# Take the earlier of two timestamps for a given signer_signature_hash
maybe_save_earlier_time() {
    local tmp_dir=$1
    local event=$2
    local hash=$3
    local timestamp=$4
    local file="$tmp_dir/${event}_${hash}"
    if [[ ! -f "$file" ]]; then
        echo "$timestamp" > "$file"
    else
        local current=$(<"$file")
        if (( $(echo "$timestamp < $current" | bc -l) )); then
            echo "$timestamp" > "$file"
        fi
    fi
}

read_time() {
    local tmp_dir=$1
    local event=$2
    local signer_signature_hash=$3
    local file="$tmp_dir/${event}_${signer_signature_hash}"
    [[ -f "$file" ]] && cat "$file" || echo "-"
}

# Get the earliest timestamp for a given signer_signature_hash
get_earliest_ts() {
    local file=$1
    local signer_signature_hash=$2
    grep "^${signer_signature_hash}|" "$file" 2>/dev/null | cut -d'|' -f2 | sort -n | head -1 || echo "-"
}
