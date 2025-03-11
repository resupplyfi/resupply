#!/bin/bash

# Define values
VERIFICATION_JSON="script/deploy/verification/verification_data.json"
ETHERSCAN_API_KEY=$ETHERSCAN_API_KEY
SEPOLIA_ETHERSCAN_API=$SEPOLIA_ETHERSCAN_API

# Define the compiler version
COMPILER_VERSION="0.8.28"

# Get the total number of contracts
num_contracts=$(jq '.contracts | length' $VERIFICATION_JSON)

# Iterate through contracts using index
for ((i=0; i<$num_contracts; i++)); do
    # Extract contract information using specific index
    name=$(jq -r ".contracts[$i].name" $VERIFICATION_JSON)
    address=$(jq -r ".contracts[$i].address" $VERIFICATION_JSON)
    types=$(jq -r ".contracts[$i].constructorArgs.types | join(\",\")" $VERIFICATION_JSON)
    
    # Get values as space-separated string, properly handling arrays
    values=$(jq -r '.contracts['$i'].constructorArgs.values | map(
        if type == "array" then 
            "[" + (map(tostring)|join(",")) + "]"
        else
            tostring
        end
    ) | join(" ")' $VERIFICATION_JSON)

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
        --verifier-url $SEPOLIA_ETHERSCAN_API \
        --compiler-version $COMPILER_VERSION \
        --watch
done