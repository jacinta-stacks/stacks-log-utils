#!/bin/zsh

# First, extract all rejection lines from signer.log into a temporary file
# This is much faster than running rg for each hash
rg "Broadcasting block response to stacks node: Rejected" ~/signer.log > /tmp/all_rejections.txt

# Now read hashes and find matches
while IFS= read -r hash; do
    # Search in the pre-filtered file
    result=$(grep "$hash" /tmp/all_rejections.txt | head -1)
    
    # Print hash and result
    if [ -n "$result" ]; then
        echo "$hash | $result"
    else
        echo "$hash | "
    fi
done < locally_rejected_hashes.txt > locally_rejected_hashes_with_logs.txt

rm /tmp/all_rejections.txt
echo "Done! Results saved to locally_rejected_hashes_with_logs.txt"
wc -l locally_rejected_hashes_with_logs.txt
