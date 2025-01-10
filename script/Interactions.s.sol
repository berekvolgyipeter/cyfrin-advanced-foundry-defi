// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { DevOpsTools } from "foundry-devops/DevOpsTools.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DSCEngine } from "src/DSCEngine.sol";

contract DepositCollateralAndMintDsc is Script {
    uint256 constant AMOUNT_COLLATERAL = 5e16;
    uint256 constant AMOUNT_TO_MINT = 10 ether;

    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helperConfig.getNetworkConfig();
        address dsceAddr = DevOpsTools.get_most_recent_deployment("DSCEngine", block.chainid);

        vm.startBroadcast(cfg.deployer);
        DSCEngine(dsceAddr).depositCollateralAndMintDsc(cfg.weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopBroadcast();
    }
}

contract RedeemCollateralForDsc is Script {
    uint256 constant AMOUNT_COLLATERAL = 1e16;
    uint256 constant AMOUNT_DSC = 1 ether;

    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helperConfig.getNetworkConfig();
        address dsceAddr = DevOpsTools.get_most_recent_deployment("DSCEngine", block.chainid);

        vm.startBroadcast(cfg.deployer);
        DSCEngine(dsceAddr).redeemCollateralForDsc(cfg.weth, AMOUNT_COLLATERAL, AMOUNT_DSC);
        vm.stopBroadcast();
    }
}
