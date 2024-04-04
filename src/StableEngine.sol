// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ReentrancyGuard} from "./libs/ReentrancyGuard.sol";
import {IERC20} from "./libs/IERC20.sol";
import {StableCoin} from "./StableCoin.sol";
import {Oracle} from "./oracles/Oracle.sol";
import {Ownable} from "./libs/Ownable.sol";
import {MathUtils, WadRayMath} from "./libs/math/MathUtils.sol";

/*
 * @title StableEngine
 * @author Miguel Bits
 *
 * The system is deisgned to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exegenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming SenUSD, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
abstract contract StableEngine is ReentrancyGuard, Ownable {
    using WadRayMath for uint256;

    constructor(string memory _name) {
        NAME = _name;
    }

    ///////////////////
    // Errors
    ///////////////////
    error StableEngine__NeedsMoreThanZero();
    error StableEngine__TokenNotAllowed(address token);
    error StableEngine__TransferFailed();
    error StableEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error StableEngine__MintFailed();
    error StableEngine__HealthFactorOk();
    error StableEngine__HealthFactorNotImproved();
    error StableEngine__VaultMintCapReached(uint256 amount);
    error StableEngine__NotEnoughCollateralToRedeem(uint256 available, uint256 amount);
    error StableEngine__NotLiquidator(address liquidator);

    /////////////////////
    // State Variables //
    /////////////////////
    string public NAME;

    bool internal initialized;

    StableCoin public sen_stable;
    Oracle public sen_oracle;

    uint256 internal LIQUIDATION_THRESHOLD; // This means you need to be 200% over-collateralized //LTV
    uint256 internal LIQUIDATION_BONUS; // This means you get assets at a 10% discount when liquidating
    uint256 internal constant MIN_HEALTH_FACTOR = 1e18;
    uint256 internal constant PRECISION = 1e18; // 1e18 = 100%

    uint256 public vaultMintCap;
    uint256 public vaultMintedAmount;
    uint256 public s_liquidationFee = 0.1 ether;
    uint256 public FEE_PERCENTAGE; //1e18 = 100%
    uint256 public INTEREST_RATE; //1e27 = 100% //per year
    address public TREASURY; // address to send fees to

    /// @dev Amount of collateral deposited by user
    mapping(address => mapping(address => uint256)) internal s_collateralDeposited;
    /// @dev Amount of SenUSD minted by user
    mapping(address => uint256) public s_SenUSDMinted;
    /// @dev Amount of SenUSD debt by user
    mapping(address => uint256) public s_SenUSD_Debt;
    mapping(address => uint40) public s_SenUSDMintedLastTimestamp;
    mapping(address => bool) public s_liquidators;
    /// @dev If we know exactly how many tokens we have, we could make this!
    address[] internal s_collateralTokens;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, uint256 indexed amountCollateral, address from, address to); // if from != to, then it was liquidated

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert StableEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (address(sen_oracle.assetPriceFeed(token)) == address(0)) {
            revert StableEngine__TokenNotAllowed(token);
        }
        _;
    }

    modifier onlyLiquidators() {
        if (!s_liquidators[msg.sender]) {
            revert StableEngine__NotLiquidator(msg.sender);
        }
        _;
    }

    ////////////////////////
    // Owner Functions //
    ///////////////////////

    function setTreasury(address _treasury) external onlyOwner {
        TREASURY = _treasury;
    }

    function changeVaultMintCap(uint256 _vaultMintCap) external onlyOwner {
        vaultMintCap = _vaultMintCap;
    }

    function setInterestRate(uint256 _interestRate) external onlyOwner {
        INTEREST_RATE = _interestRate;
    }

    function setSenecaLiquidationFee(uint256 _fee) external onlyOwner {
        s_liquidationFee = _fee;
    }

    function setLiquidator(address _liquidator, bool _isLiquidator) external onlyOwner {
        s_liquidators[_liquidator] = _isLiquidator;
    }

    ////////////////////////
    // External Functions //
    ///////////////////////

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountSenUSDToMint: The amount of SenUSD you want to mint
     * @notice This function will deposit your collateral and mint SenUSD in one transaction
     */
    function depositCollateralAndMintSenUSD(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountSenUSDToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);

        mintSenUSD(amountSenUSDToMint);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountSenUSDToBurn: The amount of SenUSD you want to burn
     * @notice This function will deposit your collateral and burn SenUSD in one transaction
     */
    function redeemCollateralForSenUSD(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountSenUSDToBurn
    ) external moreThanZero(amountCollateral) nonReentrant {
        _burnSenUSD(amountSenUSDToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have SenUSD minted, you will not be able to redeem until you burn your SenUSD
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice careful! You'll burn your SenUSD here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn
     * you SenUSD but keep your collateral in.
     */
    function burnSenUSD(uint256 amount) external moreThanZero(amount) nonReentrant {
        _burnSenUSD(amount, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your SenUSD to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of SenUSD you want to burn to cover the user's debt. Should pass the user minted amount here
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        public
        moreThanZero(debtToCover)
        nonReentrant
        onlyLiquidators
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert StableEngine__HealthFactorOk();
        }

        // If covering 100 SenUSD, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 SenUSD
        uint256 bonusCollateral = _takePercentOf(tokenAmountFromDebtCovered, LIQUIDATION_BONUS);

        //get the bonus collateral value in USD, apply the liquidation fee
        uint256 bonusCollateralValueInUsd = _getUsdValue(collateral, bonusCollateral);
        uint256 liquidationSenUSDFee = _takePercentOf(bonusCollateralValueInUsd, s_liquidationFee);
        //transfer to treasury the liquidation fee
        sen_stable.transferFrom(msg.sender, TREASURY, liquidationSenUSDFee);

        // Burn SenUSD equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        uint256 totalDepositedCollateral = s_collateralDeposited[user][collateral];
        if (totalCollateralToRedeem > totalDepositedCollateral) {
            totalCollateralToRedeem = totalDepositedCollateral;
            debtToCover = sen_oracle.getAmountPriced(totalCollateralToRedeem, collateral);
        }

        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnSenUSD(debtToCover, user, msg.sender);

        _updateDebtInterest(msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    //////////////////////
    // Public Functions //
    /////////////////////

    /*
     * @param amountSenUSDToMint: The amount of SenUSD you want to mint
     * You can only mint SenUSD if you have enough collateral
     */
    function mintSenUSD(uint256 amountSenUSDToMint) public moreThanZero(amountSenUSDToMint) nonReentrant {
        //cannot mint if health factor is not above MIN_HEALTH_FACTOR + a buffer
        if (_healthFactor(msg.sender) < MIN_HEALTH_FACTOR + 0.1 ether) {
            revert StableEngine__BreaksHealthFactor(_healthFactor(msg.sender));
        }

        if (vaultMintedAmount + amountSenUSDToMint > vaultMintCap) {
            revert StableEngine__VaultMintCapReached(vaultMintedAmount + amountSenUSDToMint);
        }

        uint256 feeTaken = _takePercentOf(amountSenUSDToMint, FEE_PERCENTAGE);
        uint256 toMint = amountSenUSDToMint - feeTaken;

        _updateDebtInterest(msg.sender);

        s_SenUSDMinted[msg.sender] += amountSenUSDToMint;
        s_SenUSD_Debt[msg.sender] += amountSenUSDToMint;

        revertIfHealthFactorIsBroken(msg.sender);

        s_SenUSDMintedLastTimestamp[msg.sender] = uint40(block.timestamp);

        bool minted = sen_stable.mint(msg.sender, toMint);
        bool feeMinted = sen_stable.mint(TREASURY, feeTaken);

        vaultMintedAmount += amountSenUSDToMint;

        if (minted != true || feeMinted != true) {
            revert StableEngine__MintFailed();
        }
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        virtual
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert StableEngine__TransferFailed();
        }
    }

    ////////////////////////
    // INTERNAL Functions //
    ///////////////////////

    function _updateDebtInterest(address _user) internal {
        s_SenUSD_Debt[_user] = getCompoundedInterestRate(_user, s_SenUSD_Debt[_user]);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        internal
        virtual
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, amountCollateral, from, to);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert StableEngine__TransferFailed();
        }
    }

    function _burnSenUSD(uint256 amountSenUSDToBurn, address onBehalfOf, address SenUSDFrom) internal {
        if (amountSenUSDToBurn > s_SenUSDMinted[onBehalfOf]) {
            amountSenUSDToBurn = s_SenUSDMinted[onBehalfOf];
        }

        _updateDebtInterest(onBehalfOf);

        //get compounded debt to cover
        uint256 cumInterest = getCompoundedInterestRate(onBehalfOf, amountSenUSDToBurn);

        bool success = sen_stable.transferFrom(SenUSDFrom, address(this), cumInterest);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert StableEngine__TransferFailed();
        }

        s_SenUSDMinted[onBehalfOf] -= amountSenUSDToBurn;
        s_SenUSD_Debt[onBehalfOf] -= cumInterest;

        //if burned the full amount, then time = 0 ; payed all borrow fees
        if (s_SenUSDMinted[onBehalfOf] == 0) {
            s_SenUSDMintedLastTimestamp[onBehalfOf] = 0;
        } else {
            s_SenUSDMintedLastTimestamp[onBehalfOf] = uint40(block.timestamp);
        }

        sen_stable.burn(amountSenUSDToBurn);
        sen_stable.transfer(TREASURY, cumInterest - amountSenUSDToBurn);
        vaultMintedAmount -= amountSenUSDToBurn;
    }

    ///////////////////////////////////////////////
    // View & Pure Functions  //
    //////////////////////////////////////////////

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalSenUSDMinted, uint256 collateralValueInUsd, uint256 totalDebt)
    {
        totalSenUSDMinted = s_SenUSDMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
        totalDebt = _getDebtToCover(user);
    }

    function _getDebtToCover(address user) internal view returns (uint256) {
        return getCompoundedInterestRate(user, s_SenUSD_Debt[user]);
    }

    function _healthFactor(address user) internal view returns (uint256) {
        (, uint256 collateralValueInUsd, uint256 totalSenUSDDebt) = _getAccountInformation(user);
        return _calculateHealthFactor(totalSenUSDDebt, collateralValueInUsd);
    }

    function _getUsdValue(address token, uint256 amount) internal view returns (uint256) {
        return sen_oracle.getAmountPriced(amount, token);
    }

    function _calculateHealthFactor(uint256 totalSenUSDDebt, uint256 collateralValueInUsd)
        internal
        view
        returns (uint256)
    {
        if (totalSenUSDDebt == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = _takePercentOf(collateralValueInUsd, LIQUIDATION_THRESHOLD);
        return (collateralAdjustedForThreshold * 1e18) / totalSenUSDDebt;
    }

    /// Liquidation Price = sendUSD Debt / Max LTV / Nominated Collateral * 100
    function _calculateLiquidationPrice(uint256 totalSenUSDDebt, uint256 nominalCollateral)
        internal
        view
        returns (uint256)
    {
        return (totalSenUSDDebt * 1e18) / (LIQUIDATION_THRESHOLD) * 1e18 / nominalCollateral;
    }

    function _calculateMaxDebt(uint256 collateralValueInUsd) internal view returns (uint256) {
        return (collateralValueInUsd * LIQUIDATION_THRESHOLD / 1e18);
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert StableEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    // This function is used to take a fee percentage from a value
    function _takePercentOf(uint256 amount, uint256 percent) internal pure returns (uint256 fee) {
        fee = (amount * percent) / PRECISION;
    }

    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////

    function calculateHealthFactor(uint256 totalSenUSDDebt, uint256 collateralValueInUsd)
        external
        view
        returns (uint256)
    {
        return _calculateHealthFactor(totalSenUSDDebt, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (
            uint256 totalSenUSDMinted,
            uint256 collateralValueInUsd,
            uint256 totalDebt,
            uint256 liqPrice,
            uint256 hf
        )
    {
        (totalSenUSDMinted, collateralValueInUsd, totalDebt) = _getAccountInformation(user);
        address[] memory arrayAssets = s_collateralTokens;
        uint256 arrayLen = arrayAssets.length;
        uint256 totalAssetAmount;
        for (uint256 i; i < arrayLen; ++i) {
            address asset = arrayAssets[i];
            totalAssetAmount += s_collateralDeposited[user][asset];
        }
        liqPrice = _calculateLiquidationPrice(totalDebt, totalAssetAmount);
        hf = _calculateHealthFactor(totalDebt, collateralValueInUsd);
    }

    function getMintedLastTimestamp(address user) external view returns (uint256) {
        return s_SenUSDMintedLastTimestamp[user];
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    ///@notice returns the value of collateral in USD, 1e18 decimal value
    function getAccountCollateralValue(address user) public view virtual returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount == 0) continue;
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        return sen_oracle.getAmountInAsset(usdAmountInWei, token);
    }

    function getLiquidationThreshold() external view returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external view returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getSenUSD() external view returns (address) {
        return address(sen_stable);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCompoundedInterestRate(address user, uint256 amount) public view returns (uint256) {
        if(amount == 0) return 0;
        uint40 time = s_SenUSDMintedLastTimestamp[user];
        if (time == 0) return amount;
        return amount.rayMul(MathUtils.calculateCompoundedInterest(INTEREST_RATE, time));
    }

    function getLiquidationPrice(address _user) external virtual view returns (uint256 liqPrice) {
        (, , uint256 totalSenUSDDebt) = _getAccountInformation(_user);
        address[] memory arrayAssets = s_collateralTokens;
        uint256 arrayLen = arrayAssets.length;
        uint256 totalAssetAmount;
        for (uint256 i; i < arrayLen; ++i) {
            address asset = arrayAssets[i];
            totalAssetAmount += s_collateralDeposited[_user][asset];
        }
        liqPrice = _calculateLiquidationPrice(totalSenUSDDebt, totalAssetAmount);
    }

    function getMaxDebt(address _user) external view returns (uint256 maxDebt) {
        uint256 collateralValueInUsd = getAccountCollateralValue(_user);
        return _calculateMaxDebt(collateralValueInUsd);
    }

    function getMaxMintable(address _user) public view returns (uint256 maxMintable) {
        uint256 collateralValueInUsd = getAccountCollateralValue(_user);
        uint256 maxDebt = _calculateMaxDebt(collateralValueInUsd);
        uint256 debt = getCompoundedInterestRate(_user, s_SenUSD_Debt[_user]);
        if (debt >= maxDebt) return 0;
        return maxDebt - debt;
    }

    function getMaxMintableWithFee(address _user) external view returns (uint256 maxMintable) {
        uint256 maxMintableWithoutFee = getMaxMintable(_user);
        return maxMintableWithoutFee - _takePercentOf(maxMintableWithoutFee, FEE_PERCENTAGE);
    }

    function calculateMintWithFee(uint256 amount) external view returns (uint256) {
        return amount - _takePercentOf(amount, FEE_PERCENTAGE);
    }

    function getDebtToCover(address _user) external view returns (uint256) {
        return _getDebtToCover(_user);
    }

    function getUserPositionInfo(address _user)
        external
        view
        returns (
            uint256 mintedAmount,
            uint256 liqPrice,
            uint256 collateralValueInUsd,
            uint256 debt,
            uint256 healthFactor
        )
    {
        (mintedAmount, collateralValueInUsd, debt) = _getAccountInformation(_user);
        healthFactor = _calculateHealthFactor(debt, collateralValueInUsd);
        address[] memory arrayAssets = s_collateralTokens;
        uint256 arrayLen = arrayAssets.length;
        uint256 totalAssetAmount;
        for (uint256 i; i < arrayLen; ++i) {
            address asset = arrayAssets[i];
            totalAssetAmount += s_collateralDeposited[_user][asset];
        }
        liqPrice = _calculateLiquidationPrice(debt, totalAssetAmount);
    }

    function getEngineSenUSDLeftToMint() external view returns (uint256) {
        return vaultMintCap - vaultMintedAmount;
    }

    function getEngineInfo()
        external
        view
        returns (
            string memory _name,
            uint256 totalSenUSDBorrowed,
            uint256 TVL,
            uint256 interestRate,
            uint256 senUSDLeftToMin,
            uint256 LTV
        )
    {
        totalSenUSDBorrowed = sen_stable.totalSupply();
        //loop all assets
        uint256 length = s_collateralTokens.length;
        address[] memory assets = s_collateralTokens;
        for (uint256 i; i < length; ++i) {
            address asset = assets[i];
            uint256 amount = IERC20(asset).balanceOf(address(this));
            TVL += sen_oracle.getAmountPriced(amount, asset);
        }
        interestRate = INTEREST_RATE;
        senUSDLeftToMin = vaultMintCap - vaultMintedAmount;
        _name = NAME;
        LTV = LIQUIDATION_THRESHOLD;
    }

    function getLiqFee(uint256 _amountBurning) external view returns (uint256) {
        return _takePercentOf(_amountBurning, s_liquidationFee);
    }
}
