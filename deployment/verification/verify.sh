#!/bin/bash

# Define values
VERIFICATION_JSON="deployment/verification/verification_data.json"  # Updated path to match actual location
ETHERSCAN_API_KEY=$ETHERSCAN_API_KEY
SEPOLIA_ETHERSCAN_API=$SEPOLIA_ETHERSCAN_API

# Check if file exists
if [ ! -f "$VERIFICATION_JSON" ]; then
    echo "Error: Verification file not found at $VERIFICATION_JSON"
    exit 1
fi

# Define the compiler version
COMPILER_VERSION="0.8.28"

# Get the total number of contracts
num_contracts=$(jq '.contracts | length' "$VERIFICATION_JSON")

# Check if jq command succeeded
if [ $? -ne 0 ]; then
    echo "Error: Failed to parse JSON file"
    exit 1
fi

# Iterate through contracts using index
for i in $(seq 0 $((num_contracts-1))); do
    # Extract contract information using specific index
    name=$(jq -r ".contracts[$i].name" "$VERIFICATION_JSON")
    address=$(jq -r ".contracts[$i].address" "$VERIFICATION_JSON")
    types=$(jq -r ".contracts[$i].constructorArgs.types | join(\",\")" "$VERIFICATION_JSON")
    
    # Get values as space-separated string, properly handling arrays
    values=$(jq -r '.contracts['$i'].constructorArgs.values | map(
        if type == "array" then 
            "[" + (map(tostring)|join(",")) + "]"
        else
            tostring
        end
    ) | join(" ")' "$VERIFICATION_JSON")

    # Debugging output
    echo "Verifying $name at $address"
    echo "Types: $types"
    echo "Values: $values"

    # Check if address and values are not empty
    if [[ -z "$address" || -z "$values" ]]; then
        echo "Error: Missing address or values for $name"
        continue
    fi

    # Create the constructor args
    constructor_args=$(cast abi-encode "constructor($types)" $values)

    # Run the forge verify-contract command
    forge verify-contract $address $name \
        --constructor-args "$constructor_args" \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --verifier-url "$ETHERSCAN_API" \
        --compiler-version $COMPILER_VERSION \
        --chain-id 1 \
        --watch
done