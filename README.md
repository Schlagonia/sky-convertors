# Sky Convertors

Tokenized Strategy converters for Sky stable assets.

The strategies inherit `BaseHealthCheck` and use Yearn Tokenized Strategy `3.1.0` live accounting by overriding `_strategyTotalAssets()`. That means current converted value is reflected in `totalAssets()` without needing keeper reports. Reports can still be called, but normal accounting does not depend on them.

Deposits are closed by default through `BaseHealthCheck.open == false`, and the loss limit stays at the `BaseHealthCheck` default of `0`.

Deposits are also disabled whenever the Sky PSM has a non-zero `tin` or `tout` fee. Withdraw paths do not revert on PSM fees.

## Strategies

- `USDCToUSDS`: accepts USDC, converts through the Sky Lite PSM wrapper, and deposits USDS into the ERC4626 vault with the standard `deposit`.
- `USDSToUSDC`: accepts USDS, converts through the Sky Lite PSM wrapper, and deposits USDC into the ERC4626 vault.
- `DAIToUSDC`: accepts DAI, converts DAI <-> USDS through the Sky DAI-USDS exchanger, then USDS <-> USDC through the Lite PSM wrapper, and deposits USDC into the ERC4626 vault.
- `USDCToSUSDS`: extends `USDCToUSDS` and only overrides `_deployFunds` to use the sUSDS referral deposit.

## Mainnet Addresses

These mainnet protocol addresses are hardcoded constants in the strategies. The target ERC4626 vault is passed to the constructor.

- USDC: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- DAI: `0x6B175474E89094C44Da98b954EedeAC495271d0F`
- USDS: `0xdC035D45d973E3EC169d2276DDab16f1e407384F`
- DAI-USDS exchanger: `0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A`
- Lite PSM wrapper: `0xA188EEC8F81263234dA3622A406892F3D630f98c`

## Build And Test

```sh
forge build
ETH_RPC_URL=<mainnet-rpc> forge test -vv
```

Tests run against a live mainnet fork only. They use real Sky, token, PSM, exchanger, configured ERC4626 vaults, and Tokenized Strategy contracts at mainnet addresses.
