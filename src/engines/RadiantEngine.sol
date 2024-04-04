// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Ownable} from "../libs/Ownable.sol";

import {ERC20, SafeTransferLib, FixedPointMathLib} from "../libs/ERC4626.sol";
import {ERC1155Supply} from "../libs/ERC1155Supply.sol";
import {ERC1155} from "../libs/ERC1155.sol";
import {ERC1155Holder, ERC1155Receiver} from "../libs/ERC1155Holder.sol";
import {StableEngine, StableCoin, Oracle} from "../StableEngine.sol";

abstract contract RadiantWrapper is ERC1155Supply, Ownable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed caller, address indexed sender, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller, address indexed receiver, address indexed sender, uint256 assets, uint256 shares
    );

    mapping(uint256 => ERC20) public radiantTokenIds;
    mapping(address => uint256) public radiantTokenAddresses;
    uint256 public currentTokenId = 0;

    modifier idExists(uint256 _id) {
        require(address(radiantTokenIds[_id]) != address(0), "INVALID_TOKEN_ID");
        _;
    }

    constructor() ERC1155("") {}

    function addRadiantToken(ERC20 radiantToken) external onlyOwner {
        currentTokenId++;
        radiantTokenIds[currentTokenId] = radiantToken;
        radiantTokenAddresses[address(radiantToken)] = currentTokenId;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function mint(uint256 tokenId, uint256 shares, address receiver)
        internal
        idExists(tokenId)
        returns (uint256 assets)
    {
        assets = previewMint(shares, tokenId); // No need to check for rounding error, previewMint rounds up.

        ERC20 asset = radiantTokenIds[tokenId];

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, tokenId, shares, "");

        emit Deposit(msg.sender, receiver, assets, shares);

        // afterDeposit(assets, shares);
    }

    function redeem(uint256 tokenId, uint256 shares, address receiver, address sender)
        internal
        idExists(tokenId)
        returns (uint256 assets)
    {
        ERC20 asset = radiantTokenIds[tokenId];

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares, tokenId)) != 0, "ZERO_ASSETS");

        // beforeWithdraw(assets, shares);

        _burn(sender, tokenId, shares);

        emit Withdraw(msg.sender, receiver, sender, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets(uint256 _id) public view returns (uint256) {
        return radiantTokenIds[_id].balanceOf(address(this));
    }

    function convertToShares(uint256 assets, uint256 _id) public view virtual returns (uint256) {
        uint256 supply = totalSupply(_id); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets(_id));
    }

    function convertToAssets(uint256 shares, uint256 _id) public view virtual returns (uint256) {
        uint256 supply = totalSupply(_id); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(_id), supply);
    }

    function previewDeposit(uint256 assets, uint256 _id) public view virtual returns (uint256) {
        return convertToShares(assets, _id);
    }

    function previewMint(uint256 shares, uint256 _id) public view virtual returns (uint256) {
        uint256 supply = totalSupply(_id); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(_id), supply);
    }

    function previewWithdraw(uint256 assets, uint256 _id) public view virtual returns (uint256) {
        uint256 supply = totalSupply(_id); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets(_id));
    }

    function previewRedeem(uint256 shares, uint256 _id) public view returns (uint256) {
        return convertToAssets(shares, _id);
    }
}

contract RadiantEngine is StableEngine, RadiantWrapper, ERC1155Holder {
    constructor(string memory _name) StableEngine(_name) {}

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

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        override
        moreThanZero(amountCollateral)
        nonReentrant
    {
        // wrapper vault mint
        mint(radiantTokenAddresses[tokenCollateralAddress], amountCollateral, address(this));

        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, amountCollateral);
    }

    ///////////////////////
    // Private Functions //
    //////////////////////
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        internal
        override
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, amountCollateral, from, to);

        //wrapper vault burn
        redeem(radiantTokenAddresses[tokenCollateralAddress], amountCollateral, to, address(this));
    }

    function getAccountCollateralValue(address user) public view override returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 1; index <= currentTokenId; index++) {
            address token = address(radiantTokenIds[index]);
            uint256 share = s_collateralDeposited[user][token];
            if (share == 0) continue;
            uint256 amount = convertToAssets(share, index); //account for radiant token rebases
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getLiquidationPrice(address _user) override external view returns (uint256 liqPrice) {
        (, , uint256 totalSenUSDDebt) = _getAccountInformation(_user);
        uint256 totalAssetAmount;
        for (uint256 index = 1; index <= currentTokenId; index++) {
            address token = address(radiantTokenIds[index]);
            uint256 share = s_collateralDeposited[_user][token];
            if (share == 0) continue;
            uint256 assetAmountDecimals = 
                10 ** (18 - ERC20(token).decimals()) * convertToAssets(share, index); //account for radiant token rebases
            totalAssetAmount += assetAmountDecimals;
        }
        liqPrice = _calculateLiquidationPrice(totalSenUSDDebt, totalAssetAmount);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, ERC1155Receiver) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
