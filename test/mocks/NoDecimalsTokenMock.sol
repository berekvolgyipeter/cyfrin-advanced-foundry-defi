// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract NoDecimalsTokenMock {
    string public name;
    string public symbol;

    constructor(string memory _name, string memory _symbol) payable {
        name = _name;
        symbol = _symbol;
    }
}
