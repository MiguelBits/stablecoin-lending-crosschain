pragma solidity 0.8.15;

import {AggregatorV3Interface} from "../libs/AggregatorV3Interface.sol";
import {Ownable} from "../libs/Ownable.sol";
import {AggregatorV2V3Interface} from "../libs/AggregatorV2V3Interface.sol";
import {FixedPointMathLib} from "../libs/FixedPointMathLib.sol";

contract Oracle is Ownable {
    using FixedPointMathLib for uint256;

    struct Decimals {
        uint256 oracle;
        uint256 asset;
    }

    error UnsupportedAsset(address asset);
    error SequencerDown();
    error GracePeriodNotOver();
    error OraclePriceZero();
    error RoundIDOutdated();

    mapping(address => Decimals) public assetDecimals;
    mapping(address => AggregatorV3Interface) public assetPriceFeed;
    uint256 constant GRACE_PERIOD_TIME = 3 hours;
    AggregatorV2V3Interface public sequencerUptimeFeed;

    constructor(address _sequencer) {
        sequencerUptimeFeed = AggregatorV2V3Interface(_sequencer);
    }

    function addAsset(address _asset, address _priceFeed, uint256 _assetDecimals, uint256 _oracleDecimals)
        external
        onlyOwner
    {
        assetPriceFeed[_asset] = AggregatorV3Interface(_priceFeed);
        assetDecimals[_asset] = Decimals(_oracleDecimals, _assetDecimals);
    }

    function getOraclePrice(address _asset) public view returns (int256) {
        AggregatorV3Interface priceFeed = assetPriceFeed[_asset];
        if (address(priceFeed) == address(0)) revert UnsupportedAsset(_asset);

        if (address(sequencerUptimeFeed) != address(0)) {
            // Source: https://docs.chain.link/data-feeds/l2-sequencer-feeds/
            (
                /*uint80 roundID*/
                ,
                int256 answer,
                uint256 startedAt,
                /*uint256 updatedAt*/
                ,
                /*uint80 answeredInRound*/
            ) = sequencerUptimeFeed.latestRoundData();

            // Answer == 0: Sequencer is up
            // Answer == 1: Sequencer is down
            bool isSequencerUp = answer == 0;
            if (!isSequencerUp) {
                revert SequencerDown();
            }
            // Make sure the grace period has passed after the sequencer is back up.
            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= GRACE_PERIOD_TIME) {
                revert GracePeriodNotOver();
            }
        }

        (uint80 roundID, int256 price,,, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (price <= 0) revert OraclePriceZero();

        if (answeredInRound < roundID) revert RoundIDOutdated();

        return price;
    }

    ///@notice Returns the spot price of an asset in USD 1e18 decimals
    function getSpotPrice(address _asset) public view returns (uint256) {
        int256 price = getOraclePrice(_asset);

        return uint256(price).mulDivUp(1e18, assetDecimals[_asset].oracle);
    }

    ///@notice Returns the spot price of an asset in asset decimals
    function getSpotPriceInAssetDecimals(address _asset) public view returns (uint256) {
        uint256 price = getSpotPrice(_asset);

        return price.mulDivUp(assetDecimals[_asset].asset, 1e18);
    }

    /// @notice Returns the amount of asset priced in USD
    /// How much USD is _amount asset worth?
    /// @dev _amount is in asset decimals
    function getAmountPriced(uint256 _amount, address _asset) external view returns (uint256) {
        //amount must be set to 18 decimals
        _amount = _amount * (1e18 / assetDecimals[_asset].asset);
        return _amount.mulDivUp(getSpotPrice(_asset), 1e18);
    }

    /// @notice Returns the amount in asset decimals of asset
    /// How much asset amount do I have of _amountPriced USD?
    /// @dev _amountPriced is 1e18 decimals * spot price, this means it is in USD
    function getAmountInAsset(uint256 _amountPriced, address _asset) external view returns (uint256 amount) {
        uint256 assetDecimalsValue = assetDecimals[_asset].asset;

        //_amountPriced must be set to assetDecimalsValue decimals
        if (assetDecimalsValue < 1e18) {
            _amountPriced = _amountPriced / (1e18 / assetDecimalsValue);
        } else if (assetDecimalsValue > 1e18) {
            _amountPriced = _amountPriced * (assetDecimalsValue / 1e18);
        }
        //amount = amountPriced / spotPrice
        amount = _amountPriced.mulDivUp(1e18, getSpotPrice(_asset));
    }
}
