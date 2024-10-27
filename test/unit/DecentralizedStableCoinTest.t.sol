// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import { Test, console2 } from "forge-std/Test.sol";
import { DecentralizedStableCoin } from "src/DecentralizedStableCoin.sol";

contract DecentralizedStablecoinTest is Test {
    address owner = makeAddr("owner");
    DecentralizedStableCoin dsc;

    function setUp() public {
        dsc = new DecentralizedStableCoin(owner);
    }

    function testMustBurnMoreThanZero() public {
        vm.startPrank(owner);
        dsc.mint(address(this), 100);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(owner);
        dsc.mint(address(this), 100);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(101);
        vm.stopPrank();
    }

    function testMustMintMoreThanZero() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.mint(address(this), 0);
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), 100);
        vm.stopPrank();
    }
}
