// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {StableCoin, Oracle} from "../src/StableEngine.sol";
import {ERC20} from "../src/libs/ERC20.sol";

contract SenUSD_Swap {
    Oracle sen_oracle;
    StableCoin sen_stable;
    ERC20 steth;
    ERC20 weth;
    ERC20 rBTC;

    constructor(address _oracle, address SenUSDAddress, address _steth, address _weth, address _rBTC) {
        sen_stable = StableCoin(SenUSDAddress);
        sen_oracle = Oracle(_oracle);
        steth = ERC20(_steth);
        weth = ERC20(_weth);
        rBTC = ERC20(_rBTC);
    }

    function swapForSenUSD(ERC20 _asset, uint256 _assetAmount) public {
        uint256 asset_amount = sen_oracle.getAmountPriced(_assetAmount, address(_asset));
        sen_stable.mint(address(this), asset_amount);
        _asset.transfer(msg.sender, asset_amount);
    }

    function mintHere() external {
        sen_stable.mint(address(this), 1000 ether);
    }
}
