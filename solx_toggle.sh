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

# --- Update foundry.toml solc settings ---
FOUNDRY_TOML="foundry.toml"
SOLX_PATH="/Users/wavey/.local/bin/solx"
LINE1="solc = \"$SOLX_PATH\""
LINE2="solc_version = \"$SOLX_PATH\""

if [ -f "$FOUNDRY_TOML" ]; then
    if [ "$DIRECTION" = "up" ]; then
        echo "Ensuring solc settings are present in $FOUNDRY_TOML below [profile.default]..."
        # Remove any existing occurrences first, then insert right after [profile.default]
        awk -v l1="$LINE1" -v l2="$LINE2" '
            BEGIN{added=0}
            # Skip existing lines anywhere in the file
            $0==l1 || $0==l2 { next }
            # When we hit [profile.default], print it and then the lines once
            /^\[profile\.default\]\s*$/ {
                print
                if (!added) {
                    print l1
                    print l2
                    added=1
                }
                next
            }
            { print }
        ' "$FOUNDRY_TOML" > "$FOUNDRY_TOML.tmp" && mv "$FOUNDRY_TOML.tmp" "$FOUNDRY_TOML"
    else
        echo "Removing solc settings from $FOUNDRY_TOML..."
        # Delete the lines anywhere in the file
        sed -i.bak "/^$(printf '%s' "$LINE1" | sed 's/[].*^$\/+?{}|()[]/\\&/g')$/d" "$FOUNDRY_TOML"
        sed -i.bak "/^$(printf '%s' "$LINE2" | sed 's/[].*^$\/+?{}|()[]/\\&/g')$/d" "$FOUNDRY_TOML"
        rm "$FOUNDRY_TOML.bak"
    fi
else
    echo "Warning: $FOUNDRY_TOML not found; skipping solc settings update."
fi
