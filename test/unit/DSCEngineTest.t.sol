// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { MockV3Aggregator } from "chainlink/tests/MockV3Aggregator.sol";
import { ERC20DecimalsMock } from "test/mocks/ERC20DecimalsMock.sol";
import { NoDecimalsTokenMock } from "test/mocks/NoDecimalsTokenMock.sol";
import {
    MockDSCFailedMint,
    MockDSCFailedTransfer,
    MockDSCFailedTransferFrom,
    MockDSCCrashPriceDuringBurn
} from "test/mocks/MockDSC.sol";
import { DeployDSC } from "script/DeployDSC.s.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DSCEngine } from "src/DSCEngine.sol";
import { DecentralizedStableCoin } from "src/DecentralizedStableCoin.sol";

abstract contract DSCEngineTest is Test {
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address token, uint256 amount);

    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig.NetworkConfig cfg;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant FEED_PRECISION = 1e8;
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant LIQUIDATION_PRECISION = 100;

    int256 public constant ETH_USD_PRICE = int256(2000 * FEED_PRECISION);
    int256 public constant ETH_USD_PLUMMETED_PRICE = int256(18 * FEED_PRECISION);
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 200;
    uint8 public constant DEFAULT_TOKEN_DECIMALS = 18;
    uint8 public constant WETH_DECIMALS = 18;
    uint8 public constant WBTC_DECIMALS = 8;

    address public user = makeAddr("user");
    uint256 public amountCollateral = 10 ether;
    uint256 public amountToMint = 100 ether;

    address public liquidator = makeAddr("liquidator");
    uint256 public amountCollateralLiquidator = 20 ether;

    address public notAllowedToken = address(new ERC20DecimalsMock("NAT", "NAT", DEFAULT_TOKEN_DECIMALS));
    address[] public tokenAddresses;
    address[] public feedAddresses;

    function setUp() public {
        HelperConfig helperConfig;
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        cfg = helperConfig.getNetworkConfig();

        tokenAddresses = [cfg.weth, cfg.wbtc];
        feedAddresses = [cfg.ethUsdPriceFeed, cfg.btcUsdPriceFeed];

        ERC20DecimalsMock(cfg.weth).mint(user, STARTING_ERC20_BALANCE);
        ERC20DecimalsMock(cfg.wbtc).mint(user, STARTING_ERC20_BALANCE);
        ERC20DecimalsMock(notAllowedToken).mint(user, STARTING_ERC20_BALANCE);
    }

    function setUpDscMintFailed() public {
        address owner = msg.sender;

        vm.startPrank(owner);
        MockDSCFailedMint mockDsc = new MockDSCFailedMint(owner);
        dsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(dsce));
        vm.stopPrank();
    }

    function setUpCollateralTransferFailed() public returns (MockDSCFailedTransfer) {
        address owner = msg.sender;

        vm.startPrank(owner);
        dsc = new DecentralizedStableCoin(owner);
        MockDSCFailedTransfer mockWeth = new MockDSCFailedTransfer(owner);
        tokenAddresses = [address(mockWeth)];
        feedAddresses = [cfg.ethUsdPriceFeed];
        dsce = new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
        mockWeth.mint(user, STARTING_ERC20_BALANCE);
        dsc.transferOwnership(address(dsce));
        vm.stopPrank();

        return mockWeth;
    }

    function setUpDscTransferFromFailed() public returns (MockDSCFailedTransferFrom) {
        address owner = msg.sender;
        vm.startPrank(owner);
        MockDSCFailedTransferFrom mockDsc = new MockDSCFailedTransferFrom(owner);
        dsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        mockDsc.mint(user, amountCollateral);
        mockDsc.transferOwnership(address(dsce));
        vm.stopPrank();

        return mockDsc;
    }

    function setUpCollateralTransferFromFailed() public returns (MockDSCFailedTransferFrom) {
        address owner = msg.sender;
        vm.startPrank(owner);
        dsc = new DecentralizedStableCoin(owner);
        MockDSCFailedTransferFrom mockWeth = new MockDSCFailedTransferFrom(owner);
        tokenAddresses = [address(mockWeth)];
        feedAddresses = [cfg.ethUsdPriceFeed];
        dsce = new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
        mockWeth.mint(user, STARTING_ERC20_BALANCE);
        dsc.transferOwnership(address(dsce));
        vm.stopPrank();

        return mockWeth;
    }

    function amountToMint100PercentCollateralized() public view returns (uint256) {
        (, int256 price,,,) = MockV3Aggregator(cfg.ethUsdPriceFeed).latestRoundData();
        return (amountCollateral * (uint256(price) * ADDITIONAL_FEED_PRECISION)) / PRECISION;
    }

    function depositCollateral(address _token) public {
        vm.startPrank(user);
        ERC20DecimalsMock(_token).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(_token, amountCollateral);
        vm.stopPrank();
    }

    function depositCollateralAndMintDsc(address _token) public {
        vm.startPrank(user);
        ERC20DecimalsMock(_token).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(_token, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function redeemCollateralForDsc(address _token, uint256 _amountRedeem, uint256 _amountBurn) public {
        vm.startPrank(user);
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralForDsc(_token, _amountRedeem, _amountBurn);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        depositCollateral(cfg.weth);
        _;
    }

    modifier mintedDsc() {
        vm.prank(user);
        dsce.mintDsc(amountToMint);
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        depositCollateralAndMintDsc(cfg.weth);
        _;
    }

    modifier liquidated() {
        ERC20DecimalsMock(cfg.weth).mint(liquidator, amountCollateralLiquidator);

        MockV3Aggregator(cfg.ethUsdPriceFeed).updateAnswer(ETH_USD_PLUMMETED_PRICE);

        vm.startPrank(liquidator);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateralLiquidator);
        dsce.depositCollateralAndMintDsc(cfg.weth, amountCollateralLiquidator, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.liquidate(cfg.weth, user, amountToMint); // whole debt is covered
        vm.stopPrank();
        _;
    }
}

contract ConstructorTest is DSCEngineTest {
    function testConstructor() public {
        DSCEngine newDsce = new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
        address[] memory collateralTokens = newDsce.getCollateralTokens();

        assertEq(collateralTokens.length, tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            assertEq(collateralTokens[i], tokenAddresses[i]);
            assertEq(newDsce.getCollateralTokenPriceFeed(tokenAddresses[i]), feedAddresses[i]);
        }
        assertEq(newDsce.getDsc(), address(dsc));
    }

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses = [cfg.weth];

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }
}

contract OwnerTest is DSCEngineTest {
    function testDSCEngineOwnsDSC() public view {
        assertEq(address(dsce), dsc.owner());
    }
}

contract PriceTest is DSCEngineTest {
    function testGetTokenAmountFromUsd() public view {
        uint256 expectedWeth = 0.05 ether;
        uint256 amountUsd = expectedWeth * uint256(ETH_USD_PRICE) * ADDITIONAL_FEED_PRECISION / PRECISION;
        uint256 amountWeth = dsce.getTokenAmountFromUsd(cfg.weth, amountUsd);
        assertEq(amountWeth, expectedWeth);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = ethAmount * uint256(ETH_USD_PRICE) * ADDITIONAL_FEED_PRECISION / PRECISION;
        uint256 actualUsd = dsce.getUsdValue(cfg.weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }
}

contract HealthFactorTest is DSCEngineTest {
    function testProperlyReportsHealthFactor() public depositedCollateral mintedDsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dsce.getHealthFactor(user);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateral mintedDsc {
        MockV3Aggregator(cfg.ethUsdPriceFeed).updateAnswer(ETH_USD_PLUMMETED_PRICE);

        uint256 userHealthFactor = dsce.getHealthFactor(user);
        // 180 * 50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION)
        // = 90 / 100 (amountToMint) = 0.9
        assert(userHealthFactor == 0.9 ether);
        // Rememeber, we need $200 at all times if we have $100 of debt
    }

    function testMaxHealthFactor() public depositedCollateral {
        assertEq(dsce.getHealthFactor(user), type(uint256).max);
    }

    function testMaxHealthFactorNoCollateral() public view {
        assertEq(dsce.getHealthFactor(user), type(uint256).max);
    }
}

contract DepositCollateralTest is DSCEngineTest {
    function testRevertsIfCollateralAmountIsZero() public {
        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(cfg.weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfNotAllowedToken() public {
        vm.startPrank(user);
        ERC20DecimalsMock(notAllowedToken).approve(address(dsce), amountCollateral);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, notAllowedToken));
        dsce.depositCollateral(notAllowedToken, amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfCollateralTransferFromFails() public {
        MockDSCFailedTransferFrom mockWeth = setUpCollateralTransferFromFailed();

        vm.prank(user);
        ERC20DecimalsMock(address(mockWeth)).approve(address(dsce), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        vm.prank(user);
        dsce.depositCollateral(address(mockWeth), amountCollateral);
    }

    function testCanDepositCollateral() public {
        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);

        vm.expectEmit(true, false, false, false, address(dsce));
        emit CollateralDeposited(user, cfg.weth, amountCollateral);
        dsce.depositCollateral(cfg.weth, amountCollateral);
        vm.stopPrank();

        assertEq(dsce.getCollateralBalance(user, cfg.weth), amountCollateral);
        assertEq(dsce.getCollateralBalance(user, cfg.wbtc), 0);
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 depositedAmount = dsce.getTokenAmountFromUsd(cfg.weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(depositedAmount, amountCollateral);
    }
}

contract MintDscTest is DSCEngineTest {
    function testRevertsIfMintAmountIsZero() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        vm.prank(user);
        dsce.mintDsc(0);
    }

    function testRevertsIfMintFails() public {
        setUpDscMintFailed();
        depositCollateral(cfg.weth);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        vm.prank(user);
        dsce.mintDsc(amountToMint);
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        amountToMint = amountToMint100PercentCollateralized();
        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(cfg.weth, amountCollateral));

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        vm.prank(user);
        dsce.mintDsc(amountToMint);
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(user);
        dsce.mintDsc(amountToMint);

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    function testGetAccountInfo() public depositedCollateral mintedDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 depositedAmount = dsce.getTokenAmountFromUsd(cfg.weth, collateralValueInUsd);
        assertEq(totalDscMinted, amountToMint);
        assertEq(depositedAmount, amountCollateral);
    }
}

contract BurnDscTest is DSCEngineTest {
    function testRevertsIfBurnAmountIsZero() public depositedCollateral mintedDsc {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        vm.prank(user);
        dsce.burnDsc(0);
    }

    function testRevertsIfDscTransferFromFails() public {
        MockDSCFailedTransferFrom mockDsc = setUpDscTransferFromFailed();
        depositCollateralAndMintDsc(address(cfg.weth));

        vm.startPrank(user);
        mockDsc.approve(address(dsce), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.burnDsc(amountToMint);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.expectRevert();
        vm.prank(user);
        dsce.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateral mintedDsc {
        vm.startPrank(user);
        dsc.approve(address(dsce), amountToMint);
        dsce.burnDsc(amountToMint);
        vm.stopPrank();

        assertEq(dsc.balanceOf(user), 0);
    }
}

contract RedeemCollateralTest is DSCEngineTest {
    function testRevertsIfCollateralAmountIsZero() public depositedCollateral mintedDsc {
        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(cfg.weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfNotAllowedToken() public depositedCollateral mintedDsc {
        vm.startPrank(user);
        ERC20DecimalsMock(notAllowedToken).approve(address(dsce), amountCollateral);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, notAllowedToken));
        dsce.redeemCollateral(notAllowedToken, amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfCollateralTransferFails() public {
        MockDSCFailedTransfer mockWeth = setUpCollateralTransferFailed();
        depositCollateral(address(mockWeth));

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        vm.prank(user);
        dsce.redeemCollateral(address(mockWeth), amountCollateral);
    }

    function testRevertsIfHealthFactorIsBroken() public depositedCollateral mintedDsc {
        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dsce.redeemCollateral(cfg.weth, amountCollateral);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        vm.expectEmit(true, false, false, false, address(dsce));
        emit CollateralRedeemed(user, user, cfg.weth, amountCollateral);
        dsce.redeemCollateral(cfg.weth, amountCollateral);

        uint256 userBalance = ERC20DecimalsMock(cfg.weth).balanceOf(user);
        assertEq(userBalance, amountCollateral);
        vm.stopPrank();
    }
}

contract DepositCollateralAndMintDscTest is DSCEngineTest {
    function testRevertsIfCollateralAmountIsZero() public {
        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateralAndMintDsc(cfg.weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateralAndMintDsc(cfg.weth, amountCollateral, 0);
        vm.stopPrank();
    }

    function testRevertsIfNotAllowedToken() public {
        vm.startPrank(user);
        ERC20DecimalsMock(notAllowedToken).approve(address(dsce), amountCollateral);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, notAllowedToken));
        dsce.depositCollateralAndMintDsc(notAllowedToken, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintFails() public {
        setUpDscMintFailed();

        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        dsce.depositCollateralAndMintDsc(cfg.weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfCollateralTransferFromFails() public {
        MockDSCFailedTransferFrom mockWeth = setUpCollateralTransferFromFailed();

        vm.prank(user);
        ERC20DecimalsMock(address(mockWeth)).approve(address(dsce), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        vm.prank(user);
        dsce.depositCollateralAndMintDsc(address(mockWeth), amountCollateral, amountToMint);
    }

    function testRevertsIfHealthFactorIsBroken() public {
        amountToMint = amountToMint100PercentCollateralized();
        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(cfg.weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.depositCollateralAndMintDsc(cfg.weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        assertEq(dsc.balanceOf(user), amountToMint);
        assertEq(dsce.getCollateralBalance(user, cfg.weth), amountCollateral);
        assertEq(dsce.getCollateralBalance(user, cfg.wbtc), 0);
    }

    function testGetAccountInfo() public depositedCollateralAndMintedDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 depositedAmount = dsce.getTokenAmountFromUsd(cfg.weth, collateralValueInUsd);
        assertEq(totalDscMinted, amountToMint);
        assertEq(depositedAmount, amountCollateral);
    }
}

contract RedeemCollateralForDscTest is DSCEngineTest {
    function testRevertsIfCollateralAmountIsZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(cfg.weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfDscAmountIsZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(cfg.weth, amountCollateral, 0);
        vm.stopPrank();
    }

    function testRevertsIfNotAllowedToken() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        ERC20DecimalsMock(notAllowedToken).approve(address(dsce), amountCollateral);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, notAllowedToken));
        dsce.redeemCollateralForDsc(notAllowedToken, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfDscTransferFromFails() public {
        MockDSCFailedTransferFrom mockDsc = setUpDscTransferFromFailed();
        depositCollateralAndMintDsc(address(cfg.weth));

        vm.startPrank(user);
        mockDsc.approve(address(dsce), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.redeemCollateralForDsc(cfg.weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfCollateralTransferFails() public {
        MockDSCFailedTransfer mockWeth = setUpCollateralTransferFailed();
        depositCollateralAndMintDsc(address(mockWeth));

        vm.startPrank(user);
        dsc.approve(address(dsce), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.redeemCollateralForDsc(address(mockWeth), amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorIsBroken() public depositedCollateralAndMintedDsc {
        uint256 amountDscToBurn = amountToMint / 2;
        uint256 amountCollateralToRedeem = amountCollateral;
        uint256 expectedHealthFactor = 0;

        vm.startPrank(user);
        dsc.approve(address(dsce), amountDscToBurn);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.redeemCollateralForDsc(cfg.weth, amountCollateralToRedeem, amountDscToBurn);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 amountRedeem = amountCollateral / 4;
        uint256 amountBurn = amountToMint / 2;

        redeemCollateralForDsc(cfg.weth, amountRedeem, amountBurn);

        assertEq(dsc.balanceOf(user), amountToMint - amountBurn);
        assertEq(dsce.getCollateralBalance(user, cfg.weth), amountCollateral - amountRedeem);
    }

    function testGetAccountInfo() public depositedCollateralAndMintedDsc {
        uint256 amountRedeem = amountCollateral / 4;
        uint256 amountBurn = amountToMint / 2;

        redeemCollateralForDsc(cfg.weth, amountRedeem, amountBurn);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 depositedAmount = dsce.getTokenAmountFromUsd(cfg.weth, collateralValueInUsd);
        assertEq(totalDscMinted, amountToMint - amountBurn);
        assertEq(depositedAmount, amountCollateral - amountRedeem);
    }
}

contract LiquidateTest is DSCEngineTest {
    function testRevertsIfDebtToCoverIsZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(liquidator);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(cfg.weth, user, 0);
        vm.stopPrank();
    }

    function testRevertsIfUserHealthFactorOk() public depositedCollateralAndMintedDsc {
        vm.startPrank(liquidator);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(cfg.weth, user, amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfUserHealthFactorNotImproved() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.startPrank(owner);
        MockDSCCrashPriceDuringBurn mockDsc = new MockDSCCrashPriceDuringBurn(cfg.ethUsdPriceFeed, owner);
        dsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(dsce));
        vm.stopPrank();

        // Arrange - User
        depositCollateralAndMintDsc(cfg.weth);

        // Arrange - Liquidator
        uint256 debtToCover = 10 ether;
        amountCollateralLiquidator = 1 ether;
        ERC20DecimalsMock(cfg.weth).mint(liquidator, amountCollateralLiquidator);

        vm.startPrank(liquidator);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateralLiquidator);
        dsce.depositCollateralAndMintDsc(cfg.weth, amountCollateralLiquidator, amountToMint);
        mockDsc.approve(address(dsce), debtToCover);

        // Act/Assert
        // ETH price gues from 2k$ to 18$ before redeem, then crashes to 0 before burn
        MockV3Aggregator(cfg.ethUsdPriceFeed).updateAnswer(ETH_USD_PLUMMETED_PRICE);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dsce.liquidate(cfg.weth, user, debtToCover);
        vm.stopPrank();
    }

    function testRevertsIfLiquidatorHealthFactorGetsBroken() public depositedCollateralAndMintedDsc {
        ERC20DecimalsMock(cfg.weth).mint(liquidator, amountCollateral);

        vm.startPrank(liquidator);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(cfg.weth, amountCollateral, amountToMint);
        vm.stopPrank();

        MockV3Aggregator(cfg.ethUsdPriceFeed).updateAnswer(ETH_USD_PLUMMETED_PRICE);
        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(cfg.weth, amountCollateral));

        vm.startPrank(liquidator);
        dsc.approve(address(dsce), amountToMint);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.liquidate(cfg.weth, user, amountToMint);
        vm.stopPrank();
    }

    function testLiquidationEmitsCollateralRedeemed() public depositedCollateralAndMintedDsc {
        MockV3Aggregator(cfg.ethUsdPriceFeed).updateAnswer(ETH_USD_PLUMMETED_PRICE);
        ERC20DecimalsMock(cfg.weth).mint(liquidator, amountCollateralLiquidator);

        vm.startPrank(liquidator);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateralLiquidator);
        dsce.depositCollateralAndMintDsc(cfg.weth, amountCollateralLiquidator, amountToMint);
        dsc.approve(address(dsce), amountToMint);

        vm.expectEmit(true, false, false, false, address(dsce));
        emit CollateralRedeemed(user, liquidator, cfg.weth, amountCollateral);
        dsce.liquidate(cfg.weth, user, amountToMint);
        vm.stopPrank();
    }

    function testLiquidationPayoutIsCorrect() public depositedCollateralAndMintedDsc liquidated {
        uint256 liquidatorWethBalance = ERC20DecimalsMock(cfg.weth).balanceOf(liquidator);
        uint256 userDscInWeth = dsce.getTokenAmountFromUsd(cfg.weth, amountToMint);
        uint256 liquidationBonusInWeth = userDscInWeth * dsce.getLiquidationBonus() / LIQUIDATION_PRECISION;
        uint256 amountLiquidated = userDscInWeth + liquidationBonusInWeth;
        uint256 hardCodedExpected = 6_111_111_111_111_111_110;

        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, amountLiquidated);
    }

    function testUserStillHasCollateralAfterLiquidation() public depositedCollateralAndMintedDsc liquidated {
        uint256 userDscInWeth = dsce.getTokenAmountFromUsd(cfg.weth, amountToMint);
        uint256 liquidationBonusInWeth = userDscInWeth * dsce.getLiquidationBonus() / LIQUIDATION_PRECISION;
        uint256 amountLiquidated = userDscInWeth + liquidationBonusInWeth;

        uint256 startingUserCollateralValueInUsd = dsce.getUsdValue(cfg.weth, amountCollateral);
        uint256 amountLiquidatedInUsd = dsce.getUsdValue(cfg.weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = startingUserCollateralValueInUsd - amountLiquidatedInUsd;

        (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 hardCodedExpectedValue = 70_000_000_000_000_000_020;

        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public depositedCollateralAndMintedDsc liquidated {
        (uint256 liquidatorDscMinted,) = dsce.getAccountInformation(liquidator);
        uint256 liquidatorDscBalance = dsc.balanceOf(liquidator);
        assertEq(liquidatorDscMinted, amountToMint);
        assertEq(liquidatorDscBalance, 0);
    }

    function testUserHasNoMoreDebt() public depositedCollateralAndMintedDsc liquidated {
        (uint256 userDscMinted,) = dsce.getAccountInformation(user);
        uint256 userDscBalance = dsc.balanceOf(user);
        assertEq(userDscMinted, 0);
        assertEq(userDscBalance, amountToMint);
    }
}

contract GetterFunctionsTest is DSCEngineTest {
    function testGetCollateralTokenPriceFeed() public view {
        assertEq(dsce.getCollateralTokenPriceFeed(cfg.weth), cfg.ethUsdPriceFeed);
        assertEq(dsce.getCollateralTokenPriceFeed(cfg.wbtc), cfg.btcUsdPriceFeed);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens[0], cfg.weth);
        assertEq(collateralTokens[1], cfg.wbtc);
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountInformation() public depositedCollateral {
        (, uint256 totalCollateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 expectedCollateralValue = dsce.getUsdValue(cfg.weth, amountCollateral);
        assertEq(totalCollateralValueInUsd, expectedCollateralValue);
    }

    function testGetCollateralBalance() public {
        vm.startPrank(user);
        ERC20DecimalsMock(cfg.weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(cfg.weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralBalance = dsce.getCollateralBalance(user, cfg.weth);
        assertEq(collateralBalance, amountCollateral);
    }

    function testGetCollateralValueInUsd() public depositedCollateral {
        uint256 collateralValue = dsce.getCollateralValueInUsd(user, cfg.weth);
        uint256 expectedCollateralValue = dsce.getUsdValue(cfg.weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetTotalCollateralValueInUsd() public depositedCollateral {
        uint256 totalCollateralValueInUsd = dsce.getTotalCollateralValueInUsd(user);
        uint256 expectedCollateralValue = dsce.getUsdValue(cfg.weth, amountCollateral);
        assertEq(totalCollateralValueInUsd, expectedCollateralValue);
    }

    function testGetDsc() public view {
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }

    function testGetPrecision() public view {
        assertEq(dsce.getPrecision(), PRECISION);
    }

    function testGetAdditionalFeedPrecision() public view {
        assertEq(dsce.getAdditionalFeedPrecision(), ADDITIONAL_FEED_PRECISION);
    }

    function testGetDefaultTokenDecimals() public view {
        assertEq(dsce.getDefaultTokenDecimals(), DEFAULT_TOKEN_DECIMALS);
    }

    function testGetTokenDecimals() public view {
        assertEq(dsce.getTokenDecimals(cfg.weth), WETH_DECIMALS);
        assertEq(dsce.getTokenDecimals(cfg.wbtc), WBTC_DECIMALS);
    }

    function testGetTokenDecimalsNoDecimals() public {
        NoDecimalsTokenMock noDecimalsToken = new NoDecimalsTokenMock("NoDecimalsToken", "NDT");
        assertEq(dsce.getTokenDecimals(address(noDecimalsToken)), DEFAULT_TOKEN_DECIMALS);
    }
}
