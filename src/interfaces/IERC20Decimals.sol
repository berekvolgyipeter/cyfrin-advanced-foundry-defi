// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

interface IERC20Decimals is IERC20 {
    function decimals() external view returns (uint8);
}
