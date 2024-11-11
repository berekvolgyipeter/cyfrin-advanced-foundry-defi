// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol) payable ERC20(name, symbol) { }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}

contract ERC20DecimalsMock is ERC20Mock {
    uint8 private immutable i_decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) payable ERC20Mock(name, symbol) {
        i_decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return i_decimals;
    }
}
