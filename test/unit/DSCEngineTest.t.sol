// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "chainlink/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "chainlink/tests/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "test/mocks/MockFailedMintDSC.sol";
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

    uint256 public constant ETH_USD_PRICE = 2000e18;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    address public user = makeAddr("user");
    uint256 public amountCollateral = 10 ether;
    uint256 public amountToMint = 100 ether;
    address public notAllowedToken = address(new ERC20Mock("NAT", "NAT", user, amountCollateral));
    address[] public tokenAddresses;
    address[] public feedAddresses;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        cfg = helperConfig.getNetworkConfig();

        ERC20Mock(cfg.weth).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(notAllowedToken).mint(user, STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(cfg.weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(cfg.weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    modifier mintedDsc() {
        vm.prank(user);
        dsce.mintDsc(amountToMint);
        _;
    }
}

contract ConstructorTest is DSCEngineTest {
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
        // Arrange - Setup
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom(owner);
        tokenAddresses = [address(mockDsc)];
        feedAddresses = [cfg.wethUsdPriceFeed];
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        mockDsc.mint(user, amountCollateral);
        mockDsc.transferOwnership(address(mockDsce));
        vm.stopPrank();
        // Arrange - user
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), amountCollateral);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockDsc), amountCollateral);
        vm.stopPrank();
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
        // Arrange - Setup
        tokenAddresses = [cfg.weth];
        feedAddresses = [cfg.wethUsdPriceFeed];
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedMintDSC mockDsc = new MockFailedMintDSC(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce));
        vm.stopPrank();
        // Arrange - user
        vm.startPrank(user);
        ERC20Mock(cfg.weth).approve(address(mockDsce), amountCollateral);
        mockDsce.depositCollateral(cfg.weth, amountCollateral);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        (, int256 price,,,) = MockV3Aggregator(cfg.wethUsdPriceFeed).latestRoundData();
        // 100% collateralized - health factor broken
        amountToMint = (amountCollateral * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();
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
