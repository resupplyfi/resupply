#!/bin/bash

# Script to switch Solidity pragma versions between 0.8.28 and 0.8.30
# Usage: ./solx_toggle.sh [up|down]

set -e

# Check if argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 [up|down]"
    echo "  up   - Switch from 0.8.28 to 0.8.30"
    echo "  down - Switch from 0.8.30 to 0.8.28"
    exit 1
fi

DIRECTION=$1

# Validate direction argument
if [ "$DIRECTION" != "up" ] && [ "$DIRECTION" != "down" ]; then
    echo "Error: Direction must be 'up' or 'down'"
    echo "Usage: $0 [up|down]"
    exit 1
fi

# Set source and target versions based on direction
if [ "$DIRECTION" = "up" ]; then
    SOURCE_VERSION="0.8.28"
    TARGET_VERSION="0.8.30"
    echo "Switching pragma from $SOURCE_VERSION to $TARGET_VERSION..."
else
    SOURCE_VERSION="0.8.30"
    TARGET_VERSION="0.8.28"
    echo "Switching pragma from $SOURCE_VERSION to $TARGET_VERSION..."
fi

# Counter for modified files
MODIFIED_COUNT=0

# Find all .sol files excluding specified directories
while IFS= read -r -d '' file; do
    # Check if file contains the source pragma
    if grep -q "pragma solidity $SOURCE_VERSION;" "$file"; then
        echo "Modifying: $file"
        
        # Replace pragma version
        sed -i.bak "s/pragma solidity $SOURCE_VERSION;/pragma solidity $TARGET_VERSION;/g" "$file"
        
        # Remove the .bak file created by sed
        rm "$file.bak"
        
        MODIFIED_COUNT=$((MODIFIED_COUNT + 1))
    fi
done < <(find . -name "*.sol" -not -path "./lib/*" -not -path "./node_modules/*" -not -path "./cache/*" -not -path "./abis/*" -print0)

echo ""
echo "Completed! Modified $MODIFIED_COUNT files."
