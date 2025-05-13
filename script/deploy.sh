#!/bin/bash

# Load environment variables
source .env

# Function to run the deployment script
run_deploy() {
    local network=$1
    local verify=$2

    echo "Deploying contracts to $network..."
    
    # Build the command
    local cmd="forge script script/Deploy.s.sol --rpc-url $network --broadcast"
    
    # Add verification if requested
    if [ "$verify" = "true" ]; then
        cmd="$cmd --verify"
    fi
    
    # Add verbosity
    cmd="$cmd -vvvv"
    
    # Execute the command
    eval $cmd
}

# Main
case "$1" in
    "local")
        run_deploy "http://localhost:8545" "false"
        ;;
    "testnet")
        run_deploy "${BASE_GOERLI_RPC:-$2}" "true"
        ;;
    "mainnet")
        run_deploy "${BASE_MAINNET_RPC:-$2}" "true"
        ;;
    *)
        echo "Usage: $0 {local|testnet|mainnet} [custom_rpc_url]"
        echo "  local    - Deploy to local Anvil network"
        echo "  testnet  - Deploy to Base Goerli testnet"
        echo "  mainnet  - Deploy to Base mainnet"
        echo ""
        echo "Examples:"
        echo "  $0 local"
        echo "  $0 testnet"
        echo "  $0 mainnet"
        echo "  $0 testnet https://custom-rpc-url"
        exit 1
        ;;
esac 