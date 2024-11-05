# Cyfrin Advanced Foundry DeFi Stablecoin

This is a section of the [Cyfrin Foundry Solidity Course](https://github.com/Cyfrin/foundry-full-course-cu?tab=readme-ov-file#advanced-foundry-section-3-foundry-defi--stablecoin-the-pinnacle-project-get-here).

The audit on the [original codebase](https://github.com/Cyfrin/foundry-defi-stablecoin-cu) can be checked [here](https://github.com/Cyfrin/foundry-defi-stablecoin-cu/blob/main/audits/codehawks-08-05-2023.md).

## Stabeloin properties

1. Relative Stability: Achored or Pegged to the US Dollar
   1. Chainlink Pricefeed
   2. Function to convert ETH & BTC to USD
2. Stability Mechanism (Minting/Burning): Algorithmicly Decentralized
   1. Users may only mint the stablecoin with enough collateral
3. Collateral: Exogenous (Crypto)
   1. wETH
   2. wBTC
