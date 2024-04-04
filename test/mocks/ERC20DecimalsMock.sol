// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "../../src/libs/ERC20.sol";

// mock class using ERC20
contract ERC20DecimalsMock is ERC20 {
    uint8 Decimals;

    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance,
        uint8 decimals
    ) payable ERC20(name, symbol) {
        _mint(initialAccount, initialBalance);
        Decimals = decimals;
    }

    function decimals() public view override returns (uint8) {
        return Decimals;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function transferInternal(address from, address to, uint256 value) public {
        _transfer(from, to, value);
    }

    function approveInternal(address owner, address spender, uint256 value) public {
        _approve(owner, spender, value);
    }
}
