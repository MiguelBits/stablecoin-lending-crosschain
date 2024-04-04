// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {StableEngine, StableCoin, Oracle} from "../StableEngine.sol";

contract SenecaEngine is StableEngine {
    constructor(string memory _name) StableEngine(_name) {}

    ///@param _liqBonus => token decimals must be same as decimals used for liq bonus !!!
    function init(
        address _oracle,
        address SenUSDAddress,
        uint256 _liqThreshold,
        uint256 _liqBonus,
        uint256 _vaultMintCap,
        uint256 _feePercentageTaken,
        uint256 _interestRate
    ) external onlyOwner {
        require(!initialized, "already initialized");

        sen_stable = StableCoin(SenUSDAddress);
        sen_oracle = Oracle(_oracle);
        LIQUIDATION_THRESHOLD = _liqThreshold;
        LIQUIDATION_BONUS = _liqBonus;
        vaultMintCap = _vaultMintCap;
        FEE_PERCENTAGE = _feePercentageTaken;
        INTEREST_RATE = _interestRate;

        initialized = true;
    }

    function add_s_collateralTokens(address _token) external onlyOwner {
        s_collateralTokens.push(_token);
    }
}
