// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { Script, console } from "forge-std/Script.sol";
import { DevOpsTools } from "foundry-devops/DevOpsTools.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";
import { HelperConfig, ANVIL_CHAIN_ID } from "script/HelperConfig.s.sol";
import { DSCEngine } from "src/DSCEngine.sol";
import { DecentralizedStableCoin } from "src/DecentralizedStableCoin.sol";

abstract contract Interaction {
    /// note: these script parameters are free to change according to needs
    uint256 constant AMOUNT_COLLATERAL_DEPOSIT = 5e16;
    uint256 constant AMOUNT_COLLATERAL_REDEEM = 1e16;
    uint256 constant AMOUNT_DSC_MINT = 10 ether;
    uint256 constant AMOUNT_DSC_BURN = 1 ether;
    uint256 constant AMOUNT_DSC_DEBT_TO_COVER = 1 ether;
    address constant USER_TO_LIQUIDATE = address(0);

    function getConfig() internal returns (HelperConfig.NetworkConfig memory cfg) {
        HelperConfig helperConfig = new HelperConfig();
        cfg = helperConfig.getNetworkConfig();

        /// @dev new collateral tokens and price feeds are created every time in anvil deployments
        if (block.chainid == ANVIL_CHAIN_ID) {
            console.log("Anvil deployment, updating tokens and feeds in config.");

            DSCEngine dsce = getDscEngine();
            address[] memory tokenAddresses = dsce.getCollateralTokens();

            cfg.weth = tokenAddresses[0];
            cfg.wbtc = tokenAddresses[1];
            cfg.ethUsdPriceFeed = dsce.getCollateralTokenPriceFeed(cfg.weth);
            cfg.btcUsdPriceFeed = dsce.getCollateralTokenPriceFeed(cfg.wbtc);
        }
    }

    function getDscEngine() internal view returns (DSCEngine dsce) {
        dsce = DSCEngine(DevOpsTools.get_most_recent_deployment("DSCEngine", block.chainid));
    }

    function getDsc() internal view returns (DecentralizedStableCoin dsc) {
        dsc = DecentralizedStableCoin(DevOpsTools.get_most_recent_deployment("DecentralizedStableCoin", block.chainid));
    }
}

contract MintMockWethAnvil is Interaction, Script {
    error MintMockWethAnvil__NotAnvilChain();

    uint256 constant AMOUNT_MOCK_WETH_MINT = 100 ether;

    function run() external {
        HelperConfig.NetworkConfig memory cfg = getConfig();
        if (block.chainid != ANVIL_CHAIN_ID) {
            revert MintMockWethAnvil__NotAnvilChain();
        }

        vm.startBroadcast(cfg.deployer);
        ERC20Mock(cfg.weth).mint(cfg.deployer, AMOUNT_MOCK_WETH_MINT);
        vm.stopBroadcast();
    }
}

contract DepositCollateral is Interaction, Script {
    function run() external {
        HelperConfig.NetworkConfig memory cfg = getConfig();
        DSCEngine dsce = getDscEngine();

        vm.startBroadcast(cfg.deployer);
        IERC20(cfg.weth).approve(address(dsce), AMOUNT_COLLATERAL_DEPOSIT);
        try dsce.depositCollateral(cfg.weth, AMOUNT_COLLATERAL_DEPOSIT) { }
        catch {
            console.log("depositCollateral reverted, revoking approval");
            IERC20(cfg.weth).approve(address(dsce), 0);
        }
        vm.stopBroadcast();
    }
}

contract RedeemCollateral is Interaction, Script {
    function run() external {
        HelperConfig.NetworkConfig memory cfg = getConfig();
        DSCEngine dsce = getDscEngine();

        vm.startBroadcast(cfg.deployer);
        dsce.redeemCollateral(cfg.weth, AMOUNT_COLLATERAL_REDEEM);
        vm.stopBroadcast();
    }
}

contract MintDsc is Interaction, Script {
    function run() external {
        HelperConfig.NetworkConfig memory cfg = getConfig();
        DSCEngine dsce = getDscEngine();

        vm.startBroadcast(cfg.deployer);
        dsce.mintDsc(AMOUNT_DSC_MINT);
        vm.stopBroadcast();
    }
}

contract BurnDsc is Interaction, Script {
    function run() external {
        HelperConfig.NetworkConfig memory cfg = getConfig();
        DSCEngine dsce = getDscEngine();
        DecentralizedStableCoin dsc = getDsc();

        vm.startBroadcast(cfg.deployer);
        dsc.approve(address(dsce), AMOUNT_DSC_BURN);
        try dsce.burnDsc(AMOUNT_DSC_BURN) { }
        catch {
            console.log("burnDsc reverted, revoking approval");
            dsc.approve(address(dsce), 0);
        }
        vm.stopBroadcast();
    }
}

contract DepositCollateralAndMintDsc is Interaction, Script {
    function run() external {
        HelperConfig.NetworkConfig memory cfg = getConfig();
        DSCEngine dsce = getDscEngine();

        vm.startBroadcast(cfg.deployer);
        IERC20(cfg.weth).approve(address(dsce), AMOUNT_COLLATERAL_DEPOSIT);
        try dsce.depositCollateralAndMintDsc(cfg.weth, AMOUNT_COLLATERAL_DEPOSIT, AMOUNT_DSC_MINT) { }
        catch {
            console.log("depositCollateralAndMintDsc reverted, revoking approval");
            IERC20(cfg.weth).approve(address(dsce), 0);
        }
        vm.stopBroadcast();
    }
}

contract RedeemCollateralForDsc is Interaction, Script {
    function run() external {
        HelperConfig.NetworkConfig memory cfg = getConfig();
        DSCEngine dsce = getDscEngine();
        DecentralizedStableCoin dsc = getDsc();

        vm.startBroadcast(cfg.deployer);
        dsc.approve(address(dsce), AMOUNT_DSC_BURN);
        try dsce.redeemCollateralForDsc(cfg.weth, AMOUNT_COLLATERAL_REDEEM, AMOUNT_DSC_BURN) { }
        catch {
            console.log("redeemCollateralForDsc reverted, revoking approval.");
            dsc.approve(address(dsce), 0);
        }
        vm.stopBroadcast();
    }
}

contract Liquidate is Interaction, Script {
    function run() external {
        HelperConfig.NetworkConfig memory cfg = getConfig();
        DSCEngine dsce = getDscEngine();
        DecentralizedStableCoin dsc = getDsc();

        vm.startBroadcast(cfg.deployer);
        dsc.approve(address(dsce), AMOUNT_DSC_DEBT_TO_COVER);
        try dsce.liquidate(cfg.weth, USER_TO_LIQUIDATE, AMOUNT_DSC_DEBT_TO_COVER) { }
        catch {
            console.log("liquidate reverted, revoking approval.");
            dsc.approve(address(dsce), 0);
        }
        vm.stopBroadcast();
    }
}
