#!/bin/bash

# Script to find NewBlock events that occur AFTER block rejections for each signer_sighash
# Usage: ./find_newblock_after_rejection.sh

SIGNER_LOG="$HOME/signer.log"
INPUT_FILE="locally_rejected_hashes_with_logs.txt"
OUTPUT_FILE="newblock_after_rejection.txt"

# Check if files exist
if [[ ! -f "$SIGNER_LOG" ]]; then
    echo "Error: $SIGNER_LOG not found"
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: $INPUT_FILE not found"
    exit 1
fi

# Clear output file
> "$OUTPUT_FILE"

echo "Processing signer signature hashes..."
echo ""

# Counter for progress
count=0
total=$(wc -l < "$INPUT_FILE")

# Read each line from the input file
while IFS='|' read -r sighash reason; do
    # Trim whitespace
    sighash=$(echo "$sighash" | xargs)
    reason=$(echo "$reason" | xargs)
    
    ((count++))
    echo -n "Processing $count/$total: $sighash..."
    
    # Use rg to find all lines with this sighash, then filter for NewBlock and Rejected
    all_events=$(rg -F -e "$sighash" "$SIGNER_LOG" | grep -e "Processing event: Some(NewBlock" -e "Broadcasting block response to stacks node: Rejected")
    
    if [[ -z "$all_events" ]]; then
        echo " (not found)"
        echo "=== $sighash ===" >> "$OUTPUT_FILE"
        echo "Rejection reason: $reason" >> "$OUTPUT_FILE"
        echo "ERROR: No events found in signer.log" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "----------------------------------------" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        continue
    fi
    
    # Find the rejection line
    rejection_found=$(echo "$all_events" | grep -n "Broadcasting block response to stacks node: Rejected" | head -1)
    
    if [[ -z "$rejection_found" ]]; then
        echo " (no rejection found)"
        echo "=== $sighash ===" >> "$OUTPUT_FILE"
        echo "Rejection reason: $reason" >> "$OUTPUT_FILE"
        echo "ERROR: No rejection found" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "----------------------------------------" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        continue
    fi
    
    # Get the line number of the rejection within the filtered events
    rejection_line_num=$(echo "$rejection_found" | cut -d: -f1)
    
    # Get NewBlock events that appear AFTER the rejection
    newblock_events=$(echo "$all_events" | tail -n +$((rejection_line_num + 1)) | grep "Processing event: Some(NewBlock")
    
    # Write results
    echo "=== $sighash ===" >> "$OUTPUT_FILE"
    echo "Rejection reason: $reason" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "Rejection:" >> "$OUTPUT_FILE"
    echo "$rejection_found" | cut -d: -f2- >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    if [[ -z "$newblock_events" ]]; then
        echo "No NewBlock events found after rejection" >> "$OUTPUT_FILE"
        echo " (no NewBlock after)"
    else
        echo "NewBlock events after rejection:" >> "$OUTPUT_FILE"
        echo "$newblock_events" >> "$OUTPUT_FILE"
        newblock_count=$(echo "$newblock_events" | wc -l)
        echo " (found $newblock_count)"
    fi
    
    echo "" >> "$OUTPUT_FILE"
    echo "----------------------------------------" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
done < "$INPUT_FILE"

echo ""
echo "Done! Results written to $OUTPUT_FILE"
echo "Total: $count hashes"
