// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "chainlink/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "test/mocks/MockFailedTransferFrom.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

abstract contract DSCEngineTest is Test {
    DeployDSC deployer;
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig cfg;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;

    address public USER = makeAddr("USER");
    address public notAllowedToken = address(new ERC20Mock("NAT", "NAT", msg.sender, 1000e8));
    address[] public tokenAddresses;
    address[] public feedAddresses;
    uint256 public constant ETH_USD_PRICE = 2000e18;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        cfg = helperConfig.getNetworkConfig();

        ERC20Mock(cfg.weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(notAllowedToken).mint(USER, STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(cfg.weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(cfg.weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }
}

contract OwnerTest is DSCEngineTest {
    function testDSCEngineOwnsDSC() public view {
        assertEq(address(dsce), dsc.owner());
    }
}

contract PriceTest is DSCEngineTest {
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = ethAmount * ETH_USD_PRICE / 1e18;
        uint256 actualUsd = dsce.getUsdValue(cfg.weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }
}

contract DepositCollateralTest is DSCEngineTest {
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(cfg.weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(cfg.weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfNotAllowedToken() public {
        vm.startPrank(USER);
        ERC20Mock(notAllowedToken).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, notAllowedToken));
        dsce.depositCollateral(notAllowedToken, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom(owner);
        tokenAddresses = [address(mockDsc)];
        feedAddresses = [cfg.wethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralSuccess() public {
        vm.startPrank(USER);
        ERC20Mock(cfg.weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectEmit(true, false, false, false, address(dsce));
        emit CollateralDeposited(USER, cfg.weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(cfg.weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 depositedAmount = dsce.getTokenAmountFromUsd(cfg.weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(depositedAmount, AMOUNT_COLLATERAL);
    }
}
