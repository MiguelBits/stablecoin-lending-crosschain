// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {ERC20} from "../src/libs/ERC4626.sol";

import {StableCoin} from "../src/StableCoin.sol";
import {SenecaEngine} from "../src/engines/SenecaEngine.sol";
import {RadiantEngine} from "../src/engines/RadiantEngine.sol";
import {SenUSD_Swap} from "./SenUSD_Swap.sol";
import {Oracle} from "../src/oracles/Oracle.sol";

//forge script SenScript --broadcast --private-key $PRIVATE_KEY --rpc-url $TESTNET_RPC_URL --verify --etherscan-api-key $ETHERSCAN_API_KEY --watch

contract SenScript is Script {

    /// CONFIGS VARIABLES
    uint256 vaultCap = 1000000 * 1e18; // 1M SenUSD
    uint256 LIQUIDATION_BONUS = 0.1 ether; // 10% liq bonus
    uint256 LIQUIDATION_THRESHOLD = 0.5 ether; // 200% LTV ratio
    uint256 FEE_PERCENTAGE = 0.01 ether; // 0.1% fee
    uint256 INTEREST_RATE = 5e26; // 0.5% interest rate
    address public treasury = address(69);

    /// testnet
    address l2sequencer = address(0);
    uint8 public constant DECIMALS = 8;
    address sethPriceFeed = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e;
    address wethPriceFeed = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e;
    address rUsdPriceFeed = 0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7;

    StableCoin stable;
    SenecaEngine sethEngine;
    SenecaEngine wethEngine;
    RadiantEngine rEngine;
    Oracle oracle;
    ERC20Mock wethMock;
    ERC20Mock stethMock;
    ERC20Mock rUSDC;

    function setMocks() public {

        //WETH
        wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);

        //STETH
        stethMock = new ERC20Mock("steth", "steth", msg.sender, 1000e8);

        rUSDC = new ERC20Mock("rUSDC", "rUSDC", msg.sender, 4200e8);

        stable = new StableCoin(address(1));
        oracle = new Oracle(l2sequencer);

        oracle.addAsset(address(wethMock), sethPriceFeed, 1e18, 1e8);
        oracle.addAsset(address(stethMock), sethPriceFeed, 1e18, 1e8);
        oracle.addAsset(address(rUSDC), rUsdPriceFeed, 1e18, 1e8);

    }

    function run()
        external
        returns (
            StableCoin,
            SenecaEngine,
            SenecaEngine,
            RadiantEngine,
            Oracle,
            ERC20Mock,
            ERC20Mock,
            ERC20Mock
        )
    {
        vm.startBroadcast();

        setMocks();

        wethEngine = new SenecaEngine("WETH");
        wethEngine.init(
            address(oracle), address(stable), LIQUIDATION_THRESHOLD, LIQUIDATION_BONUS, vaultCap, FEE_PERCENTAGE, 1e26
        );
        wethEngine.setTreasury(treasury);
        wethEngine.add_s_collateralTokens(address(wethMock));

        sethEngine = new SenecaEngine("STETH");
        sethEngine.init(
            address(oracle),
            address(stable),
            LIQUIDATION_THRESHOLD,
            LIQUIDATION_BONUS,
            vaultCap,
            FEE_PERCENTAGE,
            INTEREST_RATE
        );

        sethEngine.setTreasury(treasury);
        sethEngine.add_s_collateralTokens(address(stethMock));

        rEngine = new RadiantEngine("RADIANT");
        rEngine.init(
            address(oracle),
            address(stable),
            LIQUIDATION_THRESHOLD,
            LIQUIDATION_BONUS,
            vaultCap,
            FEE_PERCENTAGE,
            INTEREST_RATE
        );

        rEngine.addRadiantToken(ERC20(address(rUSDC)));
        rEngine.setTreasury(treasury);

        stable.allowEngineContract(address(sethEngine));
        stable.allowEngineContract(address(wethEngine));
        stable.allowEngineContract(address(rEngine));


        //assert true engine stable coin are set
        require(
            stable.engineContracts(address(sethEngine)),
            "stETH engine not set"
        );

        require(
            stable.engineContracts(address(wethEngine)),
            "wETH engine not set"
        );

        require(
            stable.engineContracts(address(rEngine)),
            "rUSDC engine not set"
        );

        //assert oracle spots are not zero
        require(
            oracle.getSpotPrice(address(wethMock)) != 0,
            "weth price not set"
        );

        require(
            oracle.getSpotPrice(address(stethMock)) != 0,
            "steth price not set"
        );

        require(
            oracle.getSpotPrice(address(rUSDC)) != 0,
            "rUSDC price not set"
        );


        vm.stopBroadcast();

        return (stable, sethEngine, wethEngine, rEngine, oracle, wethMock, stethMock, rUSDC);
    }
}