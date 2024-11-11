// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { ERC20Mock } from "chainlink/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import { DSCEngine } from "src/DSCEngine.sol";
import { DecentralizedStableCoin } from "src/DecentralizedStableCoin.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DeployDSC } from "script/DeployDSC.s.sol";
import { FailOnRevertHandler, ContinueOnRevertHandler } from "test/invariant/Handlers.t.sol";

abstract contract BaseInvariant is StdInvariant, Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig.NetworkConfig cfg;

    function setUpBase() internal {
        HelperConfig helperConfig;
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        cfg = helperConfig.getNetworkConfig();
    }

    function getUsersWithCollateral() public view virtual returns (address[] memory) { }

    function logSummary() public view virtual { }

    function invariant_protocolMustHaveMoreValueThanTotalSupplyDollars() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposted = ERC20Mock(cfg.weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(cfg.wbtc).balanceOf(address(dsce));
        uint256 wethValue = dsce.getUsdValue(cfg.weth, wethDeposted);
        uint256 wbtcValue = dsce.getUsdValue(cfg.wbtc, wbtcDeposited);

        logSummary();

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_totalDscmintedIsEqualToTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalDscMinted;
        address[] memory usersWithCollateral = getUsersWithCollateral();
        for (uint256 i = 0; i < usersWithCollateral.length; i++) {
            (uint256 dscMinted,) = dsce.getAccountInformation(usersWithCollateral[i]);
            totalDscMinted += dscMinted;
        }

        logSummary();

        assertEq(totalSupply, totalDscMinted);
    }
}

/// forge-config: default.invariant.fail-on-revert = true
contract FailOnRevertInvariants is BaseInvariant {
    FailOnRevertHandler public handler;

    function setUp() external {
        setUpBase();
        handler = new FailOnRevertHandler(dsce, dsc);
        targetContract(address(handler));
    }

    function getUsersWithCollateral() public view override returns (address[] memory) {
        return handler.getUsersWithCollateral();
    }

    function logSummary() public view override {
        handler.logSummary();
    }
}

contract ContinueOnRevertInvariants is BaseInvariant {
    ContinueOnRevertHandler public handler;

    function setUp() external {
        setUpBase();
        handler = new ContinueOnRevertHandler(dsce, dsc);
        targetContract(address(handler));
    }

    function getUsersWithCollateral() public view override returns (address[] memory) {
        return handler.getUsersWithCollateral();
    }

    function logSummary() public view override {
        handler.logSummary();
    }
}
