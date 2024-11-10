// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DecentralizedStableCoin } from "src/DecentralizedStableCoin.sol";
import { DSCEngine } from "src/DSCEngine.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helperConfig.getNetworkConfig();
        tokenAddresses = [cfg.weth, cfg.wbtc];
        priceFeedAddresses = [cfg.ethUsdPriceFeed, cfg.btcUsdPriceFeed];

        vm.startBroadcast(cfg.deployer);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(cfg.deployer);
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dsc, dscEngine, helperConfig);
    }
}
