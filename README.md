# Kyber Exclusive AMM

[![Lint](https://github.com/KyberNetwork/ks-exclusive-liquidity-sc/actions/workflows/lint.yml/badge.svg)](https://github.com/KyberNetwork/ks-exclusive-liquidity-sc/actions/workflows/lint.yml)
[![Tests](https://github.com/KyberNetwork/ks-exclusive-liquidity-sc/actions/workflows/test.yml/badge.svg)](https://github.com/KyberNetwork/ks-exclusive-liquidity-sc/actions/workflows/test.yml)

Kyber Exclusive AMM is a market maker protocol built on top of Uniswap v4 and PancakeSwap Infinity. Leveraging the power of Uniswap V4 and PancakeSwap Infinity Hooks, Kyber Exclusive AMM offers the following features:
- **Exclusive Liquidity**: Restricts the swaps on the liquidity pools created with these hooks to only the Kyberswap DEX Aggregator.
- **Equilibrium Gain (EG) Absorption**: Absorbs the excess output of a swap when the pool offers a significantly higher price than the market. The absorbed tokens, called Equilibrium Gain (EG), are then redistributed to the liquidity providers as incentives.

## Documentation

[[KEM][SC][TD] Uniswap V4 Exclusive Liquidity Hook](https://www.notion.so/kybernetwork/KEM-SC-TD-Uniswap-V4-Exclusive-Liquidity-Hook-1c026751887e80baa4eed97febdaa7c0)

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

First of all, fill the necessary information in the files in the [config](./script/config) folder:

- Address of the pool manager
- Address of the owner
- Addresses of the operators
- Address of the quote signer
- Address of the surplus recipient

These values need to be set for each `chainid` of the blockchain you want to deploy to.

For Uniswap V4 version, we need to find a suitable `salt` to deploy the hook to an address matching the hook's flags (`BEFORE_SWAP_FLAG`, `AFTER_SWAP_FLAG` and `AFTER_SWAP_RETURNS_DELTA_FLAG`).
Follow these steps to find a suitable salt and deploy the hook:

- Clone the repository [Piwi](https://github.com/thepluck/piwi), which is a salt mining tool for Uniswap V4 hooks.
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

The deployed addresses are automatically saved in the [config](./script/config) folder.
