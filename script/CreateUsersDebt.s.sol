// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

import {StableCoin} from "../src/StableCoin.sol";
import {StableEngine} from "../src/StableEngine.sol";
import {Oracle} from "../src/oracles/Oracle.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

//forge script CreateUsersDebt --broadcast --private-key $PRIVATE_KEY --rpc-url $TESTNET_RPC_URL

contract CreateUsersDebt is Script {
    address stableCoin = 0xe6E8e78D5FE62547AeF0B55E781273A5997CC79f;
    address stableEngine = 0xe2E62A3523cE749369708f3b59BBeA6a3d5Fd387;
    address oracle = 0xF5a96E2AB18B5e9DE4999ea1237F112F922FAb0e;
    address weth = 0x43fdE1F5406Ea8703Db77ecDf71973D40D7273b5;
    address steth = 0x81e67F3fA8f15bbE08dc41fEf993f5C35de3b8a8;

    StableCoin stable;
    StableEngine engine;
    Oracle pricer;
    ERC20Mock wethMock;
    ERC20Mock stethMock;

    address user = 0x5018858B5c8b3c31339B8e6b253190A150e54a03; //msg.sender

    function run() public {
        vm.startBroadcast();

        stable = StableCoin(stableCoin);
        engine = StableEngine(stableEngine);
        pricer = Oracle(oracle);
        wethMock = ERC20Mock(weth);
        stethMock = ERC20Mock(steth);

        // MockV3Aggregator aggregator = MockV3Aggregator(address(pricer.assetPriceFeed(weth)));

        // int price = pricer.getOraclePrice(weth);
        // console.log("price", uint(price));

        wethMock.mint(user, 1 ether);

        wethMock.approve(stableEngine, 1 ether);
        engine.depositCollateralAndMintSenUSD(weth, 1 ether, 500 ether); //1k SenUSD
        // engine.mintSenUSD(1 ether); //1k SenUSD

        uint256 dollar = stable.balanceOf(user);
        console.log("dollar", dollar);
        uint256 healthFactor = engine.getHealthFactor(user);
        console.log("healthFactor", healthFactor);

        //drop price
        // aggregator.updateAnswer(price/2);
        // price = pricer.getSpotPrice(weth);
        // console.log("price", price);

        // healthFactor = engine.getHealthFactor(user);
        // console.log("healthFactor", healthFactor);

        vm.stopBroadcast();
    }
}
