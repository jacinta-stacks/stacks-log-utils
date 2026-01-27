#!/bin/zsh

# First, extract all rejection lines from signer.log into a temporary file
rg "Broadcasting block response to stacks node: Rejected" ~/signer.log > /tmp/all_rejections.txt

# Now read hashes and find matches, extracting just the reason field
while IFS= read -r hash; do
    # Search in the pre-filtered file and extract reason field using sed
    result=$(grep "$hash" /tmp/all_rejections.txt | head -1 | sed -n 's/.*reason: "\([^"]*\)".*/\1/p')
    
    # Print hash and reason
    if [ -n "$result" ]; then
        echo "$hash | \"$result\""
    else
        echo "$hash | "
    fi
done < locally_rejected_hashes.txt > locally_rejected_hashes_with_logs.txt

rm /tmp/all_rejections.txt
echo "Done! Results saved to locally_rejected_hashes_with_logs.txt"
wc -l locally_rejected_hashes_with_logs.txt
