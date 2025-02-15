// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { MockV3Aggregator } from "chainlink/tests/MockV3Aggregator.sol";
import { ERC20DecimalsMock } from "test/mocks/ERC20Mock.sol";

uint256 constant ANVIL_CHAIN_ID = 31_337;
uint256 constant ETH_SEPOLIA_CHAIN_ID = 11_155_111;

contract HelperConfig is Script {
    error HelperConfig__UnknownChainId();

    struct NetworkConfig {
        address ethUsdPriceFeed;
        address btcUsdPriceFeed;
        address weth;
        address wbtc;
        uint8 wethDecimals;
        uint8 wbtcDecimals;
        address deployer;
    }

    address public constant ANVIL_ADDRESS_0 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 60_000e8;
    uint8 public constant FEED_DECIMALS = 8;
    uint8 public constant WETH_DECIMALS = 18;
    uint8 public constant WBTC_DECIMALS = 8;

    NetworkConfig public networkConfig;

    constructor() {
        if (block.chainid == ANVIL_CHAIN_ID) {
            networkConfig = getOrCreateAnvilEthConfig();
        } else if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            networkConfig = getSepoliaEthConfig();
        } else {
            revert HelperConfig__UnknownChainId();
        }
    }

    function getNetworkConfig() public view returns (NetworkConfig memory) {
        return networkConfig;
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (networkConfig.ethUsdPriceFeed != address(0)) {
            return networkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(FEED_DECIMALS, ETH_USD_PRICE);
        ERC20DecimalsMock wethMock = new ERC20DecimalsMock("WETH", "WETH", WETH_DECIMALS);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(FEED_DECIMALS, BTC_USD_PRICE);
        ERC20DecimalsMock wbtcMock = new ERC20DecimalsMock("WBTC", "WBTC", WBTC_DECIMALS);
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            ethUsdPriceFeed: address(ethUsdPriceFeed),
            btcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            wethDecimals: WETH_DECIMALS,
            wbtcDecimals: WBTC_DECIMALS,
            deployer: ANVIL_ADDRESS_0
        });
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wethDecimals: WETH_DECIMALS,
            wbtcDecimals: WBTC_DECIMALS,
            deployer: vm.envAddress("ADDRESS_DEV")
        });
    }
}
