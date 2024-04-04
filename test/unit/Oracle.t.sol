// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {Oracle} from "../../src/oracles/Oracle.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Setup} from "../Setup.t.sol";

contract OracleTest is StdCheats, Test, Setup {
    Oracle oracle;
    MockV3Aggregator ethUsdPriceFeed;
    MockV3Aggregator stethUsdPriceFeedContract;

    function setUp() public {
        (,, oracle,,, ethUsdPriceFeed, stethUsdPriceFeedContract) = deploy();
    }

    function testAddAsset() public {
        address asset = address(1);
        address priceFeed = address(2);
        uint256 assetDecimals = 8;
        uint256 oracleDecimals = 8;

        vm.startPrank(address(oracle));
        vm.expectRevert();
        oracle.addAsset(asset, priceFeed, assetDecimals, oracleDecimals);
        vm.stopPrank();

        vm.prank(oracle.owner());
        oracle.addAsset(asset, address(ethUsdPriceFeed), assetDecimals, oracleDecimals);
    }
}
