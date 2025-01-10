# Cyfrin Advanced Foundry DeFi Stablecoin

This is a section of the [Cyfrin Foundry Solidity Course](https://github.com/Cyfrin/foundry-full-course-cu?tab=readme-ov-file#advanced-foundry-section-3-foundry-defi--stablecoin-the-pinnacle-project-get-here).

The [original codebase](https://github.com/Cyfrin/foundry-defi-stablecoin-cu) has been audited which can be checked [here](https://github.com/Cyfrin/foundry-defi-stablecoin-cu/blob/main/audits/codehawks-08-05-2023.md).

The project implements a fully decentralized and algoritmically stabilized ERC20 stablecoin called DSC. The value of 1 DSC is handled as 1 USD in the protocol. Users can mint DSC if they deposit collateral at least 200% value of the minted DSC.
If a user's collateral value drops below 200%, other users may liquidate the user by burning their DSC and they receive the the same value in collateral plus an extra 10% liqudation bonus as an incentive to keep the currency collateralized. If a user liquidates herself she doesn't lose the 10% liquidation bonus to a liquidator.

## Stabeloin properties

1. Relative Stability: Achored or Pegged to the US Dollar
   1. Chainlink Pricefeed
   2. Function to convert ETH & BTC to USD
2. Stability Mechanism (Minting/Burning): Algorithmically Decentralized
   1. Users may only mint the stablecoin with enough collateral
3. Collateral: Exogenous (Crypto)
   1. wETH
   2. wBTC

## Deployment on Sepolia

### Contracts

* [DecentralizedStableCoin](https://sepolia.etherscan.io/address/0x6953688C48B0d111303b348855A3Ce8c4E16ae76)
* [DSCEngine](https://sepolia.etherscan.io/address/0xad2C82d9418061C2D5c38490451Ed69154c24AC6)

### Interactions

* [Deposit collateral and mintd DSC](https://sepolia.etherscan.io/tx/0x91d05ff052ab84b1e2f8955a4cd9f6a77739e47558297f95300326e05dc42408)
