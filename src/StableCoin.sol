// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {ERC20Burnable, ERC20} from "./libs/ERC20Burnable.sol";
import {OFTWithFee} from "../lib/solidity-examples/contracts/token/oft/v2/fee/OFTWithFee.sol";

/*
 * @title StableCoin
 * @author Miguel Bits
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
 * This is the contract meant to be owned by StableEngine. It is a ERC20 token that can be minted and burned by the StableEngine smart contract.
 */
contract StableCoin is OFTWithFee {
    error StableCoin__AmountMustBeMoreThanZero();
    error StableCoin__BurnAmountExceedsBalance();
    error StableCoin__NotZeroAddress();

    mapping(address => bool) public engineContracts;

    address public admin;

    modifier onlyAdmin() {
        require(msg.sender == admin, "StableCoin: Only owner can call this function");
        _;
    }

    modifier onlyEngineContracts() {
        require(engineContracts[msg.sender], "StableCoin: Only engine contracts can call this function");
        _;
    }

    constructor(address _lzEndpoint) OFTWithFee("senUSD", "senUSD", 18, _lzEndpoint) {
        admin = msg.sender;
    }

    function transferAdmin(address _admin) external onlyAdmin {
        admin = _admin;
    }

    function allowEngineContract(address _engineContract) external onlyAdmin {
        engineContracts[_engineContract] = true;
    }

    function disallowEngineContract(address _engineContract) external onlyAdmin {
        engineContracts[_engineContract] = false;
    }

    function burn(uint256 _amount) public onlyEngineContracts {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableCoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert StableCoin__BurnAmountExceedsBalance();
        }
        _burn(msg.sender, _amount);
    }

    function mint(address _to, uint256 _amount) external onlyEngineContracts returns (bool) {
        if (_to == address(0)) {
            revert StableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert StableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
