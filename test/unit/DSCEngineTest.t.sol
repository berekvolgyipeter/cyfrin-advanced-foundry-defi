// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce) = deployer.run();
    }

    function testDSCEngineOwnsDSC() public view {
        assertEq(address(dsce), dsc.owner());
    }
}
