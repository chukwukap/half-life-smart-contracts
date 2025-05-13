#!/bin/bash

# Load environment variables
source .env

# Function to run a script
run_script() {
    local script=$1
    local function=$2
    local args=$3
    local network=$4

    echo "Running $script..."
    if [ -z "$function" ]; then
        forge script script/$script.s.sol --rpc-url $network --broadcast --verify -vvvv
    else
        forge script script/$script.s.sol:$function $args --rpc-url $network --broadcast --verify -vvvv
    fi
}

# Deploy contracts
deploy() {
    local network=$1
    run_script "Deploy" "" "" $network
}

# Upgrade contracts
upgrade() {
    local network=$1
    run_script "Upgrade" "" "" $network
}

# Emergency actions
emergency() {
    local action=$1
    local network=$2
    run_script "Emergency" $action "" $network
}

# Update parameters
update_params() {
    local param=$1
    local value=$2
    local network=$3
    run_script "Parameters" "update$param" "$value" $network
}

# Oracle setup
setup_oracle() {
    local action=$1
    local value=$2
    local network=$3
    run_script "OracleSetup" $action "$value" $network
}

# Main
case "$1" in
    "deploy")
        deploy ${2:-$BASE_GOERLI_RPC}
        ;;
    "upgrade")
        upgrade ${2:-$BASE_GOERLI_RPC}
        ;;
    "emergency")
        emergency $2 ${3:-$BASE_GOERLI_RPC}
        ;;
    "params")
        update_params $2 $3 ${4:-$BASE_GOERLI_RPC}
        ;;
    "oracle")
        setup_oracle $2 $3 ${4:-$BASE_GOERLI_RPC}
        ;;
    *)
        echo "Usage: $0 {deploy|upgrade|emergency|params|oracle}"
        exit 1
        ;;
esac 