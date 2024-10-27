// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { MockV3Aggregator } from "chainlink/tests/MockV3Aggregator.sol";
import { ERC20Mock } from "chainlink/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public networkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 60_000e8;

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        address deployer;
    }

    address public constant ANVIL_PUBLIC_KEY_0 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11_155_111;

    constructor() {
        if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            networkConfig = getSepoliaEthConfig();
        } else {
            networkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getNetworkConfig() public view returns (NetworkConfig memory) {
        return networkConfig;
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployer: vm.envAddress("PUBLIC_KEY_DEV")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (networkConfig.wethUsdPriceFeed != address(0)) {
            return networkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            weth: address(wethMock),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            wbtc: address(wbtcMock),
            deployer: ANVIL_PUBLIC_KEY_0
        });
    }
}
