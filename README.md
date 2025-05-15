# Kyber Exclusive AMM

[![Lint](https://github.com/KyberNetwork/ks-exclusive-liquidity-sc/actions/workflows/lint.yml/badge.svg)](https://github.com/KyberNetwork/ks-exclusive-liquidity-sc/actions/workflows/lint.yml)
[![Tests](https://github.com/KyberNetwork/ks-exclusive-liquidity-sc/actions/workflows/test.yml/badge.svg)](https://github.com/KyberNetwork/ks-exclusive-liquidity-sc/actions/workflows/test.yml)

Kyber Exclusive AMM is a market maker protocol built on top of Uniswap v4 and PancakeSwap Infinity. Leveraging the power of Uniswap v4 and PancakeSwap Infinity Hooks, Kyber Exclusive AMM offers the following features:

- **Exclusive Liquidity**: Restricts the swaps on the liquidity pools created with these hooks to only the Kyberswap DEX Aggregator.
- **Equilibrium Gain (EG) Absorption**: Absorbs the excess output of a swap when the pool offers a significantly higher price than the market. The absorbed tokens, called Equilibrium Gain (EG), are then redistributed to the liquidity providers as incentives.

## Documentation

[[KEM][SC][TD] Uniswap v4 Exclusive Liquidity Hook](https://www.notion.so/kybernetwork/KEM-SC-TD-Uniswap-V4-Exclusive-Liquidity-Hook-1c026751887e80baa4eed97febdaa7c0)

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Deploy

First of all, set the necessary configurations in the [config](./script/config) folder:

- Address of the pool manager: [Uniswap v4](./script/config/uniswap-v4-pool-manager.json) or [PancakeSwap Infinity](./script/config/pancakeswap-infinity-cl-pool-manager.json)
- Address of the owner: [owner.json](./script/config/owner.json)
- Addresses of the claimalbe accounts: [claimable-accounts.json](./script/config/claimable-accounts.json)
- Addresses of the whitelisted accounts: [whitelisted-accounts.json](./script/config/whitelisted-accounts.json)
- Address of the quote signer: [quote-signer.json](./script/config/quote-signer.json)
- Address of the equilibrium-gain recipient: [eg-recipient.json](./script/config/eg-recipient.json)

These values need to be set for each `chainid` corresponding to the blockchain you want to deploy to.

For Uniswap v4 version, we need to find a suitable `salt` to deploy the hook to an address matching the hook's flags (`BEFORE_SWAP_FLAG`, `AFTER_SWAP_FLAG` and `AFTER_SWAP_RETURNS_DELTA_FLAG`).
Follow these steps to find a suitable salt and deploy the hook:

- Clone the repository [Piwi](https://github.com/thepluck/piwi), which is a salt mining tool for Uniswap v4 hooks.
- In the cloned repository, run the following command to find a suitable salt:
  ```
  $ cargo run --release -- create3 <deployer_address> C4 [--prefix <prefix>]
  ```
- Replace the `salt` variable in the `script/uniswap/Deploy.s.sol` file with the one found in the previous step.
- In this repository, run the following command to deploy the hook:
  ```shell
  $ forge script script/uniswap/Deploy.s.sol:DeployScript --rpc-url <rpc_url> --private-key <private_key>
  ```

For Pancakeswap Infinity version, follow these steps to deploy the hook:

- Replace the `salt` variable in the `script/pancakeswap/Deploy.s.sol` file with any value you want.
- In this repository, run the following command to deploy the hook:
  ```shell
  $ forge script script/pancakeswap/Deploy.s.sol:DeployScript --rpc-url <rpc_url> --private-key <private_key>
  ```

#### Deployed Salts

Uniswap v4

| Create3Factory | Deployer | Salt | Notes |
|----------------|----------|------|-------|
| 0x8Cad6A96B0a287e29bA719257d0eF431Ea6D888B | 0x47e1E291CE08ea68554583f2eC3B99351030C5F8 | 0x8329f0fb40c11ce4a94a5ba2a623c7613defcd71c59646ad71a90000048752d9 | Experimental: Ethereum, BSC, Base, Arbitrum |
| 0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab | 0x47e1E291CE08ea68554583f2eC3B99351030C5F8 | 0x9af635f21a33ab28a0b9fdf48551eb3acd9fbfbdd696d71a07dd600005ac770b | Experimental: Unichain |
|                |          |      |       |

Pancake Infinity CL

| Create3Factory | Deployer | Salt | Notes |
|----------------|----------|------|-------|
| 0x8Cad6A96B0a287e29bA719257d0eF431Ea6D888B | 0x47e1E291CE08ea68554583f2eC3B99351030C5F8 | 0x6000000000000000000000000000000d461bf33de59eeb1d4ea839fd6e78aaf2 | Experimental: BSC |
|                |          |      |       |


The deployed addresses are automatically saved in the [Uniswap v4](./script/config/uniswap-v4-kem-hook.json) or [PancakeSwap Infinity](./script/config/pancakeswap-infinity-kem-hook.json) config files.
