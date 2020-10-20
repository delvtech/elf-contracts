#!/bin/bash

## TODO: Estimate ETH_GAS

echo "Deploying contracts..."

# deploy WETH
WETH_ADDRESS=$(export ETH_GAS=1000000; dapp create WETH 2>&1 | tail -n 1)
echo "WETH=$WETH_ADDRESS"

# deploy Elf
ELF_ADDRESS=$(export ETH_GAS=5000000; dapp create Elf $WETH_ADDRESS 2>&1 | tail -n 1)
echo "ELF=$ELF_ADDRESS"

# deploy Strategy
ELF_STRATEGY_ADDRESS=$(export ETH_GAS=5000000; dapp create ElfStrategy $ELF_ADDRESS $WETH_ADDRESS 2>&1 | tail -n 1)
echo "ELF_STRATEGY=$ELF_STRATEGY_ADDRESS"

# deploy Converter
ELEMENT_CONVERTER_ADDRESS=$(export ETH_GAS=5000000; dapp create ElementConverter $WETH_ADDRESS 2>&1 | tail -n 1)
echo "ELF_CONVERTER=$ELEMENT_CONVERTER_ADDRESS"

# deploy Lender
LENDER_ADDRESS=$(export ETH_GAS=5000000; dapp create ALender $ELEMENT_CONVERTER_ADDRESS $WETH_ADDRESS 2>&1 | tail -n 1)
echo "LENDER=$LENDER_ADDRESS"

# deploy PriceOracle
PRICE_ORACLE_ADDRESS=$(export ETH_GAS=5000000; dapp create APriceOracle 2>&1 | tail -n 1)
echo "PRICE_ORACLE=$PRICE_ORACLE_ADDRESS"

ELF_DEPLOY_ADDRESS=$(export ETH_GAS=50000000; dapp create ElfDeploy 2>&1 | tail -n 1)
echo "ELF_DEPLOY=$ELF_DEPLOY_ADDRESS"

# Elf_Deploy needs to be the governance address so it can configure the contracts
echo "Set governance addresses..."
seth send $ELF_ADDRESS "setGovernance(address)" $ELF_DEPLOY_ADDRESS
seth send $ELF_STRATEGY_ADDRESS "setGovernance(address)" $ELF_DEPLOY_ADDRESS
seth send $ELEMENT_CONVERTER_ADDRESS "setGovernance(address)" $ELF_DEPLOY_ADDRESS
seth send $LENDER_ADDRESS "setGovernance(address)" $ELF_DEPLOY_ADDRESS

# Call Elf_Deploy.setUp() to configure contracts
echo "Configuring contracts..."
seth send --gas 50000000 $ELF_DEPLOY_ADDRESS "setUp(address, address, address, address, address, address)" $WETH_ADDRESS $ELF_ADDRESS $ELF_STRATEGY_ADDRESS $ELEMENT_CONVERTER_ADDRESS $LENDER_ADDRESS $PRICE_ORACLE_ADDRESS

