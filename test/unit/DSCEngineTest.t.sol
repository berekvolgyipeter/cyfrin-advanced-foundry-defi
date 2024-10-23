// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "chainlink/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "chainlink/tests/MockV3Aggregator.sol";
import {MockDSCFailedMint, MockDSCFailedTransfer, MockDSCFailedTransferFrom} from "test/mocks/MockDSC.sol";
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

    uint256 public constant ETH_USD_PRICE = 2000e18;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    address public user = makeAddr("user");
    uint256 public amountCollateral = 10 ether;
    uint256 public amountToMint = 100 ether;
    address public notAllowedToken = address(new ERC20Mock("NAT", "NAT", user, amountCollateral));
    address[] public tokenAddresses;
    address[] public feedAddresses;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address token, uint256 amount);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        cfg = helperConfig.getNetworkConfig();

        ERC20Mock(cfg.weth).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(notAllowedToken).mint(user, STARTING_ERC20_BALANCE);
    }

    function setUpMintFailed() public returns (DSCEngine) {
        tokenAddresses = [cfg.weth];
        feedAddresses = [cfg.wethUsdPriceFeed];
        address owner = msg.sender;

        vm.startPrank(owner);
        MockDSCFailedMint mockDsc = new MockDSCFailedMint(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce));
        vm.stopPrank();

        return mockDsce;
    }

    function setUpTransferFailed() public returns (DSCEngine, MockDSCFailedTransfer) {
        address owner = msg.sender;

        vm.startPrank(owner);
        MockDSCFailedTransfer mockDsc = new MockDSCFailedTransfer(owner);
        tokenAddresses = [address(mockDsc)];
        feedAddresses = [cfg.wethUsdPriceFeed];
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        mockDsc.mint(user, amountCollateral);
        mockDsc.transferOwnership(address(mockDsce));
        vm.stopPrank();

        return (mockDsce, mockDsc);
    }

    function setUpTransferFromFailed() public returns (DSCEngine, MockDSCFailedTransferFrom) {
        address owner = msg.sender;
        vm.startPrank(owner);
        MockDSCFailedTransferFrom mockDsc = new MockDSCFailedTransferFrom(owner);
        tokenAddresses = [address(mockDsc)];
        feedAddresses = [cfg.wethUsdPriceFeed];
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        mockDsc.mint(user, amountCollateral);
        mockDsc.transferOwnership(address(mockDsce));
        vm.stopPrank();

        return (mockDsce, mockDsc);
    }

    function amountToMint100PercentCollateralized() public view returns (uint256) {
        (, int256 price,,,) = MockV3Aggregator(cfg.wethUsdPriceFeed).latestRoundData();
        return (amountCollateral * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();
    }

    function depositCollateral(address _token, DSCEngine _dsce) public {
        vm.startPrank(user);
        ERC20Mock(_token).approve(address(_dsce), amountCollateral);
        _dsce.depositCollateral(_token, amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(DSCEngine _dsce) public {
        vm.prank(user);
        _dsce.mintDsc(amountToMint);
    }

    function depositCollateralAndMintDsc(DSCEngine _dsce) public {
        vm.startPrank(user);
        ERC20Mock(cfg.weth).approve(address(_dsce), amountCollateral);
        _dsce.depositCollateralAndMintDsc(cfg.weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        depositCollateral(cfg.weth, dsce);
        _;
    }

    modifier mintedDsc() {
        mintDsc(dsce);
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        depositCollateralAndMintDsc(dsce);
        _;
    }
}

contract ConstructorTest is DSCEngineTest {
    function testConstructor() public {
        tokenAddresses = [cfg.weth, cfg.wbtc];
        feedAddresses = [cfg.wethUsdPriceFeed, cfg.wbtcUsdPriceFeed];

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
        tokenAddresses.push(cfg.weth);
        feedAddresses.push(cfg.wethUsdPriceFeed);
        feedAddresses.push(cfg.wbtcUsdPriceFeed);

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
        uint256 amountUsd = expectedWeth * ETH_USD_PRICE / 1e18;
        uint256 amountWeth = dsce.getTokenAmountFromUsd(cfg.weth, amountUsd);
        assertEq(amountWeth, expectedWeth);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = ethAmount * ETH_USD_PRICE / 1e18;
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
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Rememeber, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(cfg.wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dsce.getHealthFactor(user);
        // 180 * 50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION)
        // = 90 / 100 (amountToMint) = 0.9
        assert(userHealthFactor == 0.9 ether);
    }

    function testMaxHealthFactor() public depositedCollateral {
        assertEq(dsce.getHealthFactor(user), type(uint256).max);
    }

    function testMaxHealthFactorNoCollateral() public view {
        assertEq(dsce.getHealthFactor(user), type(uint256).max);
    }
}

contract DepositCollateralTest is DSCEngineTest {
    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(cfg.weth).approve(address(dsce), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(cfg.weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfNotAllowedToken() public {
        vm.startPrank(user);
        ERC20Mock(notAllowedToken).approve(address(dsce), amountCollateral);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, notAllowedToken));
        dsce.depositCollateral(notAllowedToken, amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        (DSCEngine mockDsce, MockDSCFailedTransferFrom mockDsc) = setUpTransferFromFailed();

        vm.prank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        vm.prank(user);
        mockDsce.depositCollateral(address(mockDsc), amountCollateral);
    }

    function testCanDepositCollateral() public {
        vm.startPrank(user);
        ERC20Mock(cfg.weth).approve(address(dsce), amountCollateral);

        vm.expectEmit(true, false, false, false, address(dsce));
        emit CollateralDeposited(user, cfg.weth, amountCollateral);
        dsce.depositCollateral(cfg.weth, amountCollateral);
        vm.stopPrank();

        assertEq(dsce.getCollateralBalanceOfUser(user, cfg.weth), amountCollateral);
        assertEq(dsce.getCollateralBalanceOfUser(user, cfg.wbtc), 0);
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
        DSCEngine mockDsce = setUpMintFailed();
        depositCollateral(cfg.weth, mockDsce);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        vm.prank(user);
        mockDsce.mintDsc(amountToMint);
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
    function testRevertsIfCollateralZero() public depositedCollateral mintedDsc {
        vm.startPrank(user);
        ERC20Mock(cfg.weth).approve(address(dsce), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(cfg.weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfNotAllowedToken() public depositedCollateral mintedDsc {
        vm.startPrank(user);
        ERC20Mock(notAllowedToken).approve(address(dsce), amountCollateral);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, notAllowedToken));
        dsce.redeemCollateral(notAllowedToken, amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorIsBroken() public depositedCollateral mintedDsc {
        vm.startPrank(user);
        ERC20Mock(cfg.weth).approve(address(dsce), amountCollateral);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dsce.redeemCollateral(cfg.weth, amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfTransferFails() public {
        (DSCEngine mockDsce, MockDSCFailedTransfer mockDsc) = setUpTransferFailed();
        depositCollateral(address(mockDsc), mockDsce);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        vm.prank(user);
        mockDsce.redeemCollateral(address(mockDsc), amountCollateral);
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        vm.expectEmit(true, false, false, false, address(dsce));
        emit CollateralRedeemed(user, user, cfg.weth, amountCollateral);
        dsce.redeemCollateral(cfg.weth, amountCollateral);

        uint256 userBalance = ERC20Mock(cfg.weth).balanceOf(user);
        assertEq(userBalance, amountCollateral);
        vm.stopPrank();
    }
}

contract DepositCollateralAndMintDscTest is DSCEngineTest {
    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(cfg.weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateralAndMintDsc(cfg.weth, amountCollateral, 0);
        vm.stopPrank();
    }

    function testRevertsIfNotAllowedToken() public {
        vm.startPrank(user);
        ERC20Mock(notAllowedToken).approve(address(dsce), amountCollateral);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, notAllowedToken));
        dsce.depositCollateralAndMintDsc(notAllowedToken, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintFails() public {
        DSCEngine mockDsce = setUpMintFailed();

        vm.startPrank(user);
        ERC20Mock(cfg.weth).approve(address(mockDsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.depositCollateralAndMintDsc(cfg.weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        (DSCEngine mockDsce, MockDSCFailedTransferFrom mockDsc) = setUpTransferFromFailed();

        vm.prank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        vm.prank(user);
        mockDsce.depositCollateralAndMintDsc(address(mockDsc), amountCollateral, amountToMint);
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public {
        amountToMint = amountToMint100PercentCollateralized();
        vm.startPrank(user);
        ERC20Mock(cfg.weth).approve(address(dsce), amountCollateral);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(cfg.weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.depositCollateralAndMintDsc(cfg.weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        assertEq(dsc.balanceOf(user), amountToMint);
        assertEq(dsce.getCollateralBalanceOfUser(user, cfg.weth), amountCollateral);
        assertEq(dsce.getCollateralBalanceOfUser(user, cfg.wbtc), 0);
    }

    function testGetAccountInfo() public depositedCollateralAndMintedDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 depositedAmount = dsce.getTokenAmountFromUsd(cfg.weth, collateralValueInUsd);
        assertEq(totalDscMinted, amountToMint);
        assertEq(depositedAmount, amountCollateral);
    }
}
