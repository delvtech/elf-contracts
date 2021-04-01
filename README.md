# Element Protocol

[![Build Status](https://github.com/element-fi/elf-contracts/workflows/Tests/badge.svg)](https://github.com/element-fi/elf-contracts/actions)
[![Coverage Status](https://coveralls.io/repos/github/element-fi/elf-contracts/badge.svg?branch=main&service=github&t=7FWsvc)](https://coveralls.io/github/element-fi/elf-contracts?branch=main)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/element-fi/elf-contracts/blob/master/LICENSE)

The Element Protocol is a DeFi primitive which runs on the Ethereum blockchain. Element allows a tokenized yield bearing position to be split into principal and Yield tokens where the Principal tokens are redeemable for the deposited principal and the Yield are redeemable for the yield earned by principal earns over the period. This repository contains the smart contract which enable that functionality and a custom AMM implementation based on the YieldSpace paper. This custom AMM is designed as an integration with the Balancer V2 system.

For a technical contract overview please read our [specification](https://github.com/element-fi/elf-contracts/blob/master/SPECIFICATION.md).

Element is a community driven protocol and there are many ways to contribute to it, we encourage you to jump in and improve and use this code.

## Bugs and Feature Requests

The code in this repository's main branch is deployed to the blockchain and cannot be changed. Despite that the Element community is engaged in active development of new features and code fixes which are extension of this code. If you have a suggestion for a new feature, extension, or cool use case and want to help the community, drop by the dev channel in our [discord](https://discord.com/invite/JpctS728r9) to discuss and you will have a warm welcome!

For non security critical bugs you can open a public issue on this repository, but please follow our issue guidelines. For security critical bugs please report to security@element.fi and follow responsible disclosure standards since these contracts are likely to hold high value cryptocurrency. If you do find a bug there is a Bug Bounty program sponsored by the Element Foundation and may be further rewards allocated from other community members.

## Integrations and Code Contributions

Integrating with the Element protocol's tokens is as easy as using the ERC20 compliant tokens into your project or integrating with the public methods smart contract directly on the ethereum blockchain. Launching new assets is also permissionless but may require some new smart contract code, to write this code please carefully review the specification and ask any questions that remain in the dev channel of our [discord](https://discord.com/invite/JpctS728r9).

We welcome new code contributions and contributors, please follow out contribution [guidelines](https://github.com/element-fi/elf-contracts/blob/master/CONTRIBUTING.md). New code contributions are more likely to be accepted into future deployments of the protocol if they are discussed with our community first.

## Build and Testing

### Prerequisites

- [npm](https://nodejs.org/en/download/)

### Setup

```
git clone git@github.com:element-fi/elf-contracts.git
```

```
cd elf-contracts
npm install
```

### Build

```
npm run build
```

### Test

```
npm run test
```
