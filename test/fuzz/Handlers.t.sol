// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { EnumerableSet } from "openzeppelin/utils/structs/EnumerableSet.sol";
import { ERC20Mock } from "chainlink/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "chainlink/tests/MockV3Aggregator.sol";
import { DSCEngine, AggregatorV3Interface } from "src/DSCEngine.sol";
import { DecentralizedStableCoin } from "src/DecentralizedStableCoin.sol";

abstract contract BaseHandler is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;

    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    address public sender;
    EnumerableSet.AddressSet internal usersWithCollateral;

    modifier depositedCollateral(uint256 senderSeed) {
        if (usersWithCollateral.length() == 0) return;
        sender = usersWithCollateral.at(senderSeed % usersWithCollateral.length());
        _;
    }

    modifier depositedCollateralOrNot(uint256 senderSeed) {
        uint256 numUsers = usersWithCollateral.length();
        uint256 randomIndex = senderSeed % (numUsers + 1);

        if (randomIndex == numUsers) {
            sender = makeAddr("noCollateral");
        } else {
            sender = usersWithCollateral.at(randomIndex);
        }
        _;
    }

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(wbtc)));
    }

    /* ==================== DSCEngine FUNCTIONS ======================================== */
    function depositCollateral(uint256 collateralSeed, uint256 amount) public virtual {
        amount = boundSilent(amount, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(dsce), amount);

        dsce.depositCollateral(address(collateral), amount);
        vm.stopPrank();

        usersWithCollateral.add(msg.sender);
    }

    /* ==================== HELPER FUNCTIONS ======================================== */
    function getCollateralFromSeed(uint256 collateralSeed) internal view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function getValidOrInvalidCollateralAddressFromSeed(uint256 collateralSeed) internal view returns (address) {
        uint256 selector = collateralSeed % 3;
        if (selector == 0) {
            return address(weth);
        } else if (selector == 1) {
            return address(wbtc);
        } else {
            return address(0);
        }
    }

    function getUserToBeLiquidatedFromSeed(uint256 addressSeed) internal view returns (address) {
        if (usersWithCollateral.length() == 0) return address(0);
        address userToBeLiquidated = usersWithCollateral.at(addressSeed % usersWithCollateral.length());
        if (userToBeLiquidated == sender) return address(0);
        return userToBeLiquidated;
    }

    function boundSilent(uint256 x, uint256 min, uint256 max) internal pure returns (uint256 result) {
        return _bound(x, min, max);
    }

    /* ==================== PUBLIC HELPER FUNCTIONS ======================================== */
    function getUsersWithCollateral() public view returns (address[] memory) {
        uint256 numUsers = usersWithCollateral.length();
        address[] memory users = new address[](numUsers);

        for (uint256 i = 0; i < usersWithCollateral.length(); i++) {
            users[i] = usersWithCollateral.at(i);
        }

        return users;
    }

    function logSummary() public view virtual {
        console2.log("Weth total deposited: %s", weth.balanceOf(address(dsce)));
        console2.log("Wbtc total deposited: %s", wbtc.balanceOf(address(dsce)));
        console2.log("Total supply of DSC: %s", dsc.totalSupply());
    }
}

contract FailOnRevertHandler is BaseHandler {
    uint256 public depositCollateral_called = 0;
    uint256 public redeemCollateral_called = 0;
    uint256 public mintDsc_called = 0;
    uint256 public burnDsc_called = 0;
    uint256 public liquidate_called = 0;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) BaseHandler(_dsce, _dsc) { }

    /* ==================== DSCEngine FUNCTIONS ======================================== */
    function depositCollateral(uint256 collateralSeed, uint256 amount) public override {
        super.depositCollateral(collateralSeed, amount);
        depositCollateral_called++;
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral,
        uint256 senderSeed
    )
        public
        depositedCollateral(senderSeed)
    {
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dsce.getAccountInformation(sender);
        uint256 collateralBalance = dsce.getCollateralBalance(sender, address(collateral));

        int256 maxCollateralUsd = int256(totalCollateralValueInUsd) - 2 * int256(totalDscMinted);
        if (maxCollateralUsd <= 0) return;

        uint256 maxCollateral = dsce.getTokenAmountFromUsd(address(collateral), uint256(maxCollateralUsd));
        if (collateralBalance < maxCollateral) maxCollateral = collateralBalance;

        amountCollateral = boundSilent(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) return;

        vm.prank(sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);

        redeemCollateral_called++;
    }

    function mintDsc(uint256 amount, uint256 senderSeed) public depositedCollateral(senderSeed) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);

        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint <= 0) return;

        amount = boundSilent(amount, 0, uint256(maxDscToMint));
        if (amount == 0) return;

        vm.prank(sender);
        dsce.mintDsc(amount);

        mintDsc_called++;
    }

    function burnDsc(uint256 amount, uint256 senderSeed) public depositedCollateral(senderSeed) {
        amount = boundSilent(amount, 0, dsc.balanceOf(sender));
        if (amount == 0) return;

        vm.startPrank(sender);
        dsc.approve(address(dsce), amount);
        dsce.burnDsc(amount);
        vm.stopPrank();

        burnDsc_called++;
    }

    // TODO: implement price change to be able to liquidate
    function liquidate(
        uint256 collateralSeed,
        uint256 userToBeLiquidatedSeed,
        uint256 debtToCover,
        uint256 senderSeed
    )
        public
        depositedCollateral(senderSeed)
    {
        address userToBeLiquidated = getUserToBeLiquidatedFromSeed(userToBeLiquidatedSeed);
        if (userToBeLiquidated == address(0)) return;

        uint256 minHealthFactor = dsce.getMinHealthFactor();
        uint256 userHealthFactor = dsce.getHealthFactor(userToBeLiquidated);
        if (userHealthFactor >= minHealthFactor) return;

        debtToCover = boundSilent(debtToCover, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);

        vm.prank(sender);
        dsce.liquidate(address(collateral), userToBeLiquidated, debtToCover);

        liquidate_called++;
    }

    function callAllGetters(address user, uint256 collateralSeed, uint256 amount) public view {
        address token = getValidOrInvalidCollateralAddressFromSeed(collateralSeed);

        dsce.getAdditionalFeedPrecision();
        dsce.getCollateralTokens();
        dsce.getLiquidationBonus();
        dsce.getLiquidationThreshold();
        dsce.getMinHealthFactor();
        dsce.getPrecision();
        dsce.getDsc();
        dsce.getTokenAmountFromUsd(token, amount);
        dsce.getCollateralTokenPriceFeed(token);
        dsce.getCollateralBalance(user, token);
        dsce.getTotalCollateralValueInUsd(user);
    }

    /* ==================== HELPER FUNCTIONS ======================================== */
    function logSummary() public view override {
        super.logSummary();
        console2.log("depositCollateral_called: %s", depositCollateral_called);
        console2.log("redeemCollateral_called: %s", redeemCollateral_called);
        console2.log("mintDsc_called: %s", mintDsc_called);
        console2.log("burnDsc_called: %s", burnDsc_called);
        console2.log("liquidate_called: %s", liquidate_called);
    }
}

contract ContinueOnRevertHandler is BaseHandler {
    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) BaseHandler(_dsce, _dsc) { }

    /* ==================== DSCEngine FUNCTIONS ======================================== */
    function depositCollateral(uint256 collateralSeed, uint256 amount) public override {
        super.depositCollateral(collateralSeed, amount);
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amount,
        uint256 senderSeed
    )
        public
        depositedCollateralOrNot(senderSeed)
    {
        amount = boundSilent(amount, 0, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);

        vm.prank(sender);
        dsce.redeemCollateral(address(collateral), amount);
    }

    function mintDsc(uint256 amount, uint256 senderSeed) public depositedCollateralOrNot(senderSeed) {
        amount = boundSilent(amount, 0, uint256(MAX_DEPOSIT_SIZE));

        vm.prank(sender);
        dsce.mintDsc(amount);
    }

    function burnDsc(uint256 amount, uint256 senderSeed) public depositedCollateralOrNot(senderSeed) {
        vm.startPrank(sender);
        dsc.approve(address(dsce), amount);
        dsce.burnDsc(amount);
        vm.stopPrank();
    }

    // TODO: implement price change to be able to liquidate
    function liquidate(
        uint256 collateralSeed,
        uint256 userToBeLiquidatedSeed,
        uint256 debtToCover,
        uint256 senderSeed
    )
        public
        depositedCollateralOrNot(senderSeed)
    {
        address userToBeLiquidated = getUserToBeLiquidatedFromSeed(userToBeLiquidatedSeed);
        if (userToBeLiquidated == address(0)) return;

        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);
        vm.prank(sender);
        dsce.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    }

    /* ==================== DecentralizedStableCoin FUNCTIONS ======================================== */
    function transferDsc(uint256 amount, address to, uint256 senderSeed) public depositedCollateralOrNot(senderSeed) {
        amount = boundSilent(amount, 0, dsc.balanceOf(sender));
        vm.prank(sender);
        dsc.transfer(to, amount);
    }

    /**
     * bug changing the price can brake the protocol
     * - if the collateral price drops too fast, there is a chance that users can't liquidate each other
     * - there is no automated liquidation mechanism, only incentivization
     */
    /* ==================== Aggregator FUNCTIONS ======================================== */
    // function updateCollateralPrice(uint96 newPrice, uint256 collateralSeed) public {
    //     int256 intNewPrice = int256(uint256(newPrice));
    //     ERC20Mock collateral = getCollateralFromSeed(collateralSeed);
    //     MockV3Aggregator priceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(collateral)));

    //     priceFeed.updateAnswer(intNewPrice);
    // }
}
