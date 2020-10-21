#!/bin/bash

set -e 

ELF_DEPLOY_ADDRESS=$(export ETH_GAS=20000000; dapp create ElfDeploy 2>&1 | tail -n 1)

echo "ELF_DEPLOY=$ELF_DEPLOY_ADDRESS"

echo ""

echo "Deploying contracts..."
seth send --gas 8000000 $ELF_DEPLOY_ADDRESS "init()"

echo ""

ELF_ADDRESS=$(seth call $ELF_DEPLOY_ADDRESS "elf()(address)")
echo "ELF=$ELF_ADDRESS"

echo ""

echo "Configuring contracts..."
seth send --gas 20000000 $ELF_DEPLOY_ADDRESS "config()"

