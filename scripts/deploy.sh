#!/bin/bash

set -e

ELF_DEPLOY_ADDRESS=$(seth --gas 90000000 --rpc-accounts send --create $(cat out/ElfDeploy.bin) 2>&1 | tail -n 1)

echo "ELF_DEPLOY=$ELF_DEPLOY_ADDRESS"

echo ""

echo "Deploying contracts..."
seth --rpc-accounts send --gas 100000000 $ELF_DEPLOY_ADDRESS "init()"

echo ""

echo "Configuring contracts..."
seth --rpc-accounts send --gas 30000000 $ELF_DEPLOY_ADDRESS "config()"

echo ""
ELF_ADDRESS=$(seth call $ELF_DEPLOY_ADDRESS "elf()(address)")
echo "ELF=$ELF_ADDRESS"

WETH_ADDRESS=$(seth call $ELF_DEPLOY_ADDRESS "weth()(address)")
echo "WETH=$WETH_ADDRESS"

CONTRACT_ADDRESSES='{"ELF_DEPLOY":"%s","ELF_PROXY":"%s","ELF":"%s","WETH":"%s"}\n'
printf "$CONTRACT_ADDRESSES" "$ELF_DEPLOY_ADDRESS" "$PROXY_ADDRESS" "$ELF_ADDRESS" "$WETH_ADDRESS"> ./out/contracts.json