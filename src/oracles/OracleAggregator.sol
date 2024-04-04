// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {AggregatorV3Interface} from "../libs/AggregatorV3Interface.sol";

/// @author MiguelBits
contract OracleAggregator {
    /**
     *
     * @dev  for example: oracle1 would be stETH / USD, while oracle2 would be ETH / USD oracle
     *
     */
    address public oracle1;
    address public oracle2;

    uint8 public decimals;

    AggregatorV3Interface internal priceFeed1;
    AggregatorV3Interface internal priceFeed2;

    /**
     * @notice Contract constructor
     * @param _oracleBase Oracle address for the base asset ex: stETH / ETH
     * @param _oracleDenominator Oracle address for the denominator asset ex: ETH / USD
     */
    constructor(address _oracleBase, address _oracleDenominator) {
        require(_oracleBase != address(0), "oracle1 cannot be the zero address");
        require(_oracleDenominator != address(0), "oracle2 cannot be the zero address");
        require(_oracleBase != _oracleDenominator, "Cannot be same Oracle");

        priceFeed1 = AggregatorV3Interface(_oracleBase);
        priceFeed2 = AggregatorV3Interface(_oracleDenominator);

        require((priceFeed1.decimals() == priceFeed2.decimals()), "Decimals must be the same");

        require(decimals <= 18, "Decimals must be less than 18");

        oracle1 = _oracleBase;
        oracle2 = _oracleDenominator;
        decimals = 18;
    }

    /**
     * @notice Returns oracle-fed data from the latest round
     * @return roundID Current round id
     * @return nowPrice Current price
     * @return startedAt Starting timestamp
     * @return timeStamp Current timestamp
     * @return answeredInRound Round id for which answer was computed
     */
    function latestRoundData()
        public
        view
        returns (uint80 roundID, int256 nowPrice, uint256 startedAt, uint256 timeStamp, uint80 answeredInRound)
    {
        (uint80 roundID1, int256 price1, uint256 startedAt1, uint256 timeStamp1, uint80 answeredInRound1) =
            priceFeed1.latestRoundData();
        require(price1 > 0, "Chainlink price <= 0");
        require(answeredInRound1 >= roundID1, "RoundID from Oracle is outdated!");
        require(timeStamp1 != 0, "Timestamp == 0 !");

        (int256 price2, uint256 timeStamp2) = getOracle2_Price();

        int256 WAD = 1e18;
        nowPrice = (price1 * WAD) / price2; //divWadDown() from FixedPointMathLib.sol

        //require the difference between the two timestamps to be less than 1 hour
        if (timeStamp1 > timeStamp2) {
            require(timeStamp1 - timeStamp2 < 3600, "Timestamp difference is too large!");
        } else {
            require(timeStamp2 - timeStamp1 < 3600, "Timestamp difference is too large!");
        }

        return (roundID1, nowPrice, startedAt1, timeStamp1, answeredInRound1);
    }

    /* solhint-disbable-next-line func-name-mixedcase */
    /**
     * @notice Lookup first oracle price
     * @return price Current first oracle price, timestamp of last update
     */
    function getOracle1_Price() public view returns (int256, uint256) {
        (uint80 roundID1, int256 price1,, uint256 timeStamp1, uint80 answeredInRound1) = priceFeed1.latestRoundData();

        require(price1 > 0, "Chainlink price <= 0");
        require(answeredInRound1 >= roundID1, "RoundID from Oracle is outdated!");
        require(timeStamp1 != 0, "Timestamp == 0 !");

        return (price1, timeStamp1);
    }

    /* solhint-disbable-next-line func-name-mixedcase */
    /**
     * @notice Lookup second oracle price
     * @return price Current second oracle price, timestamp of last update
     */
    function getOracle2_Price() public view returns (int256, uint256) {
        (uint80 roundID2, int256 price2,, uint256 timeStamp2, uint80 answeredInRound2) = priceFeed2.latestRoundData();

        require(price2 > 0, "Chainlink price <= 0");
        require(answeredInRound2 >= roundID2, "RoundID from Oracle is outdated!");
        require(timeStamp2 != 0, "Timestamp == 0 !");

        return (price2, timeStamp2);
    }
}
