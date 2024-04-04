// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import "forge-std/Test.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {StableCoin} from "../src/StableCoin.sol";
import {SenecaEngine} from "../src/engines/SenecaEngine.sol";
import {RadiantEngine} from "../src/engines/RadiantEngine.sol";
import {Oracle} from "../src/oracles/Oracle.sol";

contract Setup is Test {
    address admin = address(1);
    address liquidator = address(2);
    address user = address(3);

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    /// CONFIGS VARIABLES
    uint256 public vaultCap = 1000000 * 1e18; // 1M SenUSD
    uint256 LIQUIDATION_BONUS = 0.1 ether; // 10% liq bonus
    uint256 LIQUIDATION_THRESHOLD = 0.5 ether; // 200% LTV ratio
    uint256 FEE_PERCENTAGE = 0.01 ether; // 1% fee
    uint256 INTEREST_RATE = 500000000000000000 * 1e9; // 5% anual interest rate, 1e27 value
    /// testnet
    address l2sequencer = address(0);
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant STETH_USD_PRICE = 2100e8;
    address public treasury = address(69);

    function deploy()
        internal
        returns (
            StableCoin stable,
            SenecaEngine stableEngine,
            Oracle oracle,
            ERC20Mock wethMock,
            ERC20Mock stethMock,
            MockV3Aggregator ethUsdPriceFeed,
            MockV3Aggregator stethUsdPriceFeedContract
        )
    {
        // console.log(36500e27);

        vm.startPrank(admin);
        //WETH
        ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );

        wethMock = new ERC20Mock("WETH", "WETH", admin, 1000e18);
        address weth = address(wethMock);
        address wethUsdPriceFeed = address(ethUsdPriceFeed);

        //STETH
        stethUsdPriceFeedContract = new MockV3Aggregator(
            DECIMALS,
            STETH_USD_PRICE
        );

        stethMock = new ERC20Mock("steth", "steth", admin, 2000e18);
        address steth = address(stethMock);
        address stethUsdPriceFeed = address(stethUsdPriceFeedContract);

        tokenAddresses = [weth, steth];

        stable = new StableCoin(address(1));
        oracle = new Oracle(l2sequencer);
        oracle.addAsset(weth, wethUsdPriceFeed, 1e18, 1e8);
        oracle.addAsset(steth, stethUsdPriceFeed, 1e18, 1e8);

        stableEngine = new SenecaEngine("LiquidStaking");
        stableEngine.init(
            address(oracle),
            address(stable),
            LIQUIDATION_THRESHOLD,
            LIQUIDATION_BONUS,
            vaultCap,
            FEE_PERCENTAGE,
            INTEREST_RATE
        );

        stableEngine.setTreasury(treasury);
        stableEngine.add_s_collateralTokens(weth);
        stableEngine.add_s_collateralTokens(steth);

        assertTrue(stableEngine.TREASURY() == treasury);

        // assertTrue(stableEngine.LIQUIDATION_THRESHOLD() == LIQUIDATION_THRESHOLD);
        // assertTrue(stableEngine.LIQUIDATION_BONUS() == LIQUIDATION_BONUS);
        // assertTrue(stableEngine.VAULT_CAP() == vaultCap);
        assertTrue(stableEngine.FEE_PERCENTAGE() == FEE_PERCENTAGE);

        stable.allowEngineContract(address(stableEngine));

        vm.stopPrank();
    }

    function deployRadiant()
        internal
        returns (
            StableCoin stable,
            RadiantEngine stableEngine,
            Oracle oracle,
            ERC20Mock wethMock,
            ERC20Mock stethMock,
            MockV3Aggregator ethUsdPriceFeed,
            MockV3Aggregator stethUsdPriceFeedContract
        )
    {
        vm.startPrank(admin);
        //WETH
        ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );

        wethMock = new ERC20Mock("WETH", "WETH", admin, 1000e18);
        address weth = address(wethMock);
        address wethUsdPriceFeed = address(ethUsdPriceFeed);

        //STETH
        stethUsdPriceFeedContract = new MockV3Aggregator(
            DECIMALS,
            STETH_USD_PRICE
        );

        stethMock = new ERC20Mock("steth", "steth", admin, 2000e18);
        address steth = address(stethMock);
        address stethUsdPriceFeed = address(stethUsdPriceFeedContract);

        stable = new StableCoin(address(1));
        oracle = new Oracle(l2sequencer);
        oracle.addAsset(weth, wethUsdPriceFeed, 1e18, 1e8);
        oracle.addAsset(steth, stethUsdPriceFeed, 1e18, 1e8);

        stableEngine = new RadiantEngine("Radiant");
        stableEngine.init(
            address(oracle),
            address(stable),
            LIQUIDATION_THRESHOLD,
            LIQUIDATION_BONUS,
            vaultCap,
            FEE_PERCENTAGE,
            INTEREST_RATE
        );

        stableEngine.setTreasury(treasury);
        assertTrue(stableEngine.TREASURY() == treasury);

        // assertTrue(stableEngine.LIQUIDATION_THRESHOLD() == LIQUIDATION_THRESHOLD);
        // assertTrue(stableEngine.LIQUIDATION_BONUS() == LIQUIDATION_BONUS);
        // assertTrue(stableEngine.VAULT_CAP() == vaultCap);
        assertTrue(stableEngine.FEE_PERCENTAGE() == FEE_PERCENTAGE);

        stable.allowEngineContract(address(stableEngine));

        vm.stopPrank();
    }

    function depositCollateral(SenecaEngine stableEngine, ERC20Mock[] memory tokens, uint256[] memory amounts) public {
        uint256 len = tokens.length;
        for (uint256 i; i < len; ++i) {
            _depositCollateral(stableEngine, tokens[i], amounts[i]);
        }
    }

    function depositMint(
        SenecaEngine stableEngine,
        ERC20Mock[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory dollars
    ) public {
        uint256 len = tokens.length;
        for (uint256 i; i < len; ++i) {
            //approve
            tokens[i].approve(address(stableEngine), amounts[i]);
            stableEngine.depositCollateralAndMintSenUSD(address(tokens[i]), amounts[i], dollars[i]);
            assertTrue(stableEngine.s_SenUSDMinted(user) > 0);
        }
        console.log("minted: %s", stableEngine.s_SenUSDMinted(user));
        uint256 health = stableEngine.getHealthFactor(user);
        if (health != type(uint256).max) {
            console.log("nextHealth: %s", health);
        }
    }

    function _depositCollateral(SenecaEngine stableEngine, ERC20Mock token, uint256 amount) internal {
        console.log("depositing %s", amount);
        address asset = address(token);
        token.approve(address(stableEngine), amount);
        stableEngine.depositCollateral(asset, amount);

        uint256 health = stableEngine.getHealthFactor(user);
        if (health != type(uint256).max) {
            console.log("nextHealth: %s", health);
        }
    }

    function getStableOnSecondaryMarket(address engine, StableCoin stable, uint256 amount, address to) internal {
        console.log("getting  :", amount);
        vm.startPrank(engine);
        stable.mint(to, amount);
        vm.stopPrank();
        console.log("new balan:", stable.balanceOf(to));
    }

    function _mintStableCoin(SenecaEngine stableEngine, uint256 amount) internal {
        console.log("minting %s", amount);
        stableEngine.mintSenUSD(amount);
        uint256 minted = stableEngine.s_SenUSDMinted(user);
        console.log("minted: %s", minted);
        assertTrue(minted > 0);
        uint256 health = stableEngine.getHealthFactor(user);
        if (health != type(uint256).max) {
            console.log("nextHealth: %s", health);
        }
    }

    function _updatePrice(MockV3Aggregator oracle, SenecaEngine stableEngine, int256 price) internal {
        vm.warp(block.timestamp + 1 days);
        console.log("updating price to %s", uint256(price));
        oracle.updateAnswer(price);
        uint256 newHealth = stableEngine.getHealthFactor(user);
        console.log("nextHealth: %s", newHealth);
    }

    function _repayStableCoin(SenecaEngine stableEngine, uint256 amount, uint256 burning) internal {
        console.log("repaying  :%s", amount);
        stableEngine.sen_stable().approve(address(stableEngine), burning);
        stableEngine.burnSenUSD(amount);
        uint256 health = stableEngine.getHealthFactor(user);
        if (health != type(uint256).max) {
            console.log("nextHealth: %s", health);
        }
    }

    function _liquidate(
        SenecaEngine stableEngine,
        StableCoin stable,
        ERC20Mock token,
        address who,
        uint256 burning,
        uint256 amount
    ) internal {
        console.log("liquidating %s", amount);
        console.log("healthFactor: %s", stableEngine.getHealthFactor(who));

        uint256 prev_liquidator_balance = token.balanceOf(liquidator);
        uint256 prev_engine_balance = token.balanceOf(address(stableEngine));

        ERC20Mock(address(stable)).approve(address(stableEngine), burning);

        stableEngine.liquidate(address(token), who, amount);
        uint256 health = stableEngine.getHealthFactor(who);

        if (health != type(uint256).max) {
            console.log("nextHealth: %s", health);
        }

        assertTrue(token.balanceOf(liquidator) > prev_liquidator_balance);
        assertTrue(token.balanceOf(address(stableEngine)) < prev_engine_balance);
    }
}
