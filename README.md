# Element Protocol

[![Build Status](https://github.com/element-fi/elf-contracts/workflows/Tests/badge.svg)](https://github.com/element-fi/elf-contracts/actions)
[![Coverage Status](https://coveralls.io/repos/github/element-fi/elf-contracts/badge.svg?branch=main&service=github&t=7FWsvc)](https://coveralls.io/github/element-fi/elf-contracts?branch=main)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/element-fi/elf-contracts/blob/master/LICENSE)

The Element Protocol is a DeFi primitive which runs on the Ethereum blockchain. The Protocol, at its core, allows a tokenized yield bearing position (ETH, BTC, USDC, etc) to be split into two separate tokens, the 1) principal token, and the 2) yield token. The principal tokens are redeemable for the deposited principal and the yield tokens are redeemable for the yield earned over the term period. This splitting mechanism allows users to sell their principal as a fixed-rate income position, further leveraging or increasing exposure to interest without any liquidation risk.

This repository contains the smart contracts which enable the functionality described above, including a custom AMM implementation based on the YieldSpace [paper](https://yield.is/YieldSpace.pdf), designed as an integration with the Balancer V2 system.

Element is a community driven protocol and there are many ways to contribute to it, we encourage you to jump in and improve and use this code.

For a technical contract overview please read our [specification](https://github.com/element-fi/elf-contracts/blob/master/SPECIFICATION.md).

## Bugs and Feature Requests

The code in this repository's main branch is deployed to the Ethereum blockchain and cannot be changed. Despite that, the Element community is engaged in the active development of new features and code fixes which are an extension of this code. If you have a suggestion for a new feature, extension, or cool use case and want to help the community, drop by the dev channel in our [discord](https://discord.com/invite/JpctS728r9) to discuss and you will have a warm welcome!

For non-security-critical bugs, you can open a public issue on this repository, but please follow our issue guidelines. For any security-related critical bugs please report to security@element.fi and follow responsible disclosure standards since these contracts are likely to hold high-value cryptocurrency. If you do find a bug there is a Bug Bounty program funded by Element Finance [here](https://element.fi/security). Additionally, the Element Finance Bug Bounty program has been extended to the [Immunefi platform](https://immunefi.com/bounty/elementfinance/).

## Integrations and Code Contributions

Integrating with the Element protocol's tokens is as easy as adding ERC20 compliant tokens to your project or integrating with the public methods smart contract directly on the Ethereum blockchain. Launching new assets on Element is also permissionless but may require some new smart contract code; to write this code please carefully review the specification and don't hesitate to reach out and ask any questions in the dev channel of our [discord](https://discord.com/invite/JpctS728r9).

We welcome new contributors and code contributions with open arms! Please be sure to follow our contribution [guidelines](https://github.com/element-fi/elf-contracts/blob/master/CONTRIBUTING.md) when proposing any new code. Lastly, because Element is a community driven protocol, any new code contributions are more likely to be accepted into future deployments of the protocol if they have been openly discussed within the community first.

## Build and Testing

### 1. Getting Started (Prerequisites)

- [Install npm](https://nodejs.org/en/download/)

### 2. Setup

```
git clone git@github.com:element-fi/elf-contracts.git
```

```
cd elf-contracts
npm install
npm run load-contracts
```

### 3. Build

```
npm run build
```

### 4. Test

```
npm run test
```

## Contract Addresses

Deployed contract addresses can be found in the [changelog site](https://element-fi.github.io/elf-deploy).

> Note: The highest release version will always contain the latest list of contract addresses.

Additionally, the latest deployed contract addresses for Goerli and Mainnet can be found [here](https://github.com/element-fi/elf-deploy/blob/main/addresses/goerli.json) and [here](https://github.com/element-fi/elf-deploy/blob/main/addresses/mainnet.json) respectively.
