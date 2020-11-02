#!/bin/bash

set -e

ELF_DEPLOY_ADDRESS=$(seth --gas 9007199254740991 --rpc-accounts send --create $(cat out/ElfDeploy.bin) 2>&1 | tail -n 1)

echo "ELF_DEPLOY=$ELF_DEPLOY_ADDRESS"

echo ""

echo "Deploying contracts..."
seth --rpc-accounts send --gas 9007199254740991 $ELF_DEPLOY_ADDRESS "init()"

echo ""

ELF_ADDRESS=$(seth call $ELF_DEPLOY_ADDRESS "elf()(address)")
echo "ELF=$ELF_ADDRESS"

echo ""

echo "Configuring contracts..."
seth --rpc-accounts send --gas 9007199254740991 $ELF_DEPLOY_ADDRESS "config()"
