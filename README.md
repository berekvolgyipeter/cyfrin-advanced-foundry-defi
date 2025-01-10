# Cyfrin Advanced Foundry DeFi Stablecoin

This is a section of the [Cyfrin Foundry Solidity Course](https://github.com/Cyfrin/foundry-full-course-cu?tab=readme-ov-file#advanced-foundry-section-3-foundry-defi--stablecoin-the-pinnacle-project-get-here).

The [original codebase](https://github.com/Cyfrin/foundry-defi-stablecoin-cu) has been audited which can be checked [here](https://github.com/Cyfrin/foundry-defi-stablecoin-cu/blob/main/audits/codehawks-08-05-2023.md).

The project implements a fully decentralized and algoritmically stabilized ERC20 stablecoin called DSC. The value of 1 DSC is handled as 1 USD in the protocol. Users can mint DSC if they deposit collateral at least 200% value of the minted DSC.
If a user's collateral value drops below 200%, other users may liquidate the user by burning their DSC and they receive the the same value in collateral plus an extra 10% liqudation bonus as an incentive to keep the currency collateralized. If a user liquidates herself she doesn't lose the 10% liquidation bonus to a liquidator.

## Stabeloin properties

1. Relative Stability: Achored or Pegged to the US Dollar
   1. [Chainlink Pricefeed](https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1)
   2. Function to convert ETH & BTC to USD
2. Stability Mechanism (Minting/Burning): Algorithmically Decentralized
   1. Users may only mint the stablecoin with enough collateral
3. Collateral: Exogenous (Crypto)
   1. [WETH](https://coinmarketcap.com/academy/article/what-is-wrapped-ethereum-weth)
   2. [WBTC](https://www.wbtc.network)

## Deployment on Sepolia

### Contracts

* [DecentralizedStableCoin](https://sepolia.etherscan.io/address/0x6953688C48B0d111303b348855A3Ce8c4E16ae76)
* [DSCEngine](https://sepolia.etherscan.io/address/0xad2C82d9418061C2D5c38490451Ed69154c24AC6)

### Interactions

* [Deposit collateral and mint DSC](https://sepolia.etherscan.io/tx/0x07c482c5d235c88ec2747b4fa18c533f9f212e8867a1a3522920e831c21af197)
* [Redeem collateral for DSC](https://sepolia.etherscan.io/tx/0x12435fd5f05ce29dbffd931a65e97a95bcbb493beedfe5e1965f1ecb8d8666b7)
* [Deposit collateral](https://sepolia.etherscan.io/tx/0xa6af2ed2f609e96aabe63cd2654340866e09f5defc06a012f4ab662ad7774bb5)
* [Redeem collateral](https://sepolia.etherscan.io/tx/0x3c30eb1741c74a295b5829ee70b1daa220a8f9ae1e298e680543028cffbf3526)
* [Mint DSC](https://sepolia.etherscan.io/tx/0x7ecdca5616b230d0fbb6986bbbf52a8467dac4cb7725464e006d2347b13a921f)
* [Burn DSC](https://sepolia.etherscan.io/tx/0x168500ffce3d3c444e7adc8fd7d36a9aa9a9f544fede5cb1c6620cb0bd852e76)
