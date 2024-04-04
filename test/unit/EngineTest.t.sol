pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {Setup} from "../Setup.t.sol";

import {StableCoin} from "../../src/StableCoin.sol";
import {StableEngine} from "../../src/StableEngine.sol";
import {SenecaEngine} from "../../src/engines/SenecaEngine.sol";
import {Oracle} from "../../src/oracles/Oracle.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract EngineTest is Test, Setup {
    StableCoin stable;
    SenecaEngine stableEngine;
    Oracle oracle;
    ERC20Mock wethMock;
    ERC20Mock stethMock;
    MockV3Aggregator wethOracle;
    MockV3Aggregator stethOracle;

    function setUp() public {
        (stable, stableEngine, oracle, wethMock, stethMock, wethOracle, stethOracle) = deploy();
    }

    function test_Mint() public {
        uint256 amount = 1 ether;
        uint256 borrowed = 100 ether;
        user = address(3);

        //MINT COLLATERAL
        wethMock.mint(user, amount);
        stethMock.mint(user, amount);
        //log balances
        console.log("wethMock.balanceOf(user):  %s", wethMock.balanceOf(user));
        console.log("stethMock.balanceOf(user): %s", stethMock.balanceOf(user));

        //DEPOSIT COLLATERAL
        vm.startPrank(user);
        _depositCollateral(stableEngine, wethMock, amount);
        _depositCollateral(stableEngine, stethMock, amount);
        vm.stopPrank();

        //MINT STABLE
        // uint dollar = oracle.getAmountPriced(amount, address(wethMock));
        // console.log("dollar: %s", dollar);
        uint256 dollar = stableEngine.getAccountCollateralValue(user);
        console.log("dollar: %s", dollar);
        vm.startPrank(user);
        _mintStableCoin(stableEngine, borrowed);
        assertTrue(stableEngine.getHealthFactor(user) >= 1e18);
        vm.stopPrank();

        console.log("stable treasury balance", stable.balanceOf(treasury));
        assertTrue(stable.balanceOf(treasury) > 0);
    }

    function test_Engine() public {
        uint256 prev_balanceTreasury_stable = stable.balanceOf(treasury);
        console.log("prev_balanceTreasury_stable: %s", prev_balanceTreasury_stable);

        user = admin;
        uint256 balanceWETH = wethMock.balanceOf(admin);
        uint256 balanceSTETH = stethMock.balanceOf(admin);
        // console.log("balanceWETH: %s", balanceWETH);
        // console.log("balanceSTETH: %s", balanceSTETH);

        //DEPOSIT COLLATERAL
        vm.startPrank(admin);
        _depositCollateral(stableEngine, wethMock, balanceWETH / 2);
        _depositCollateral(stableEngine, stethMock, balanceSTETH / 2);
        vm.stopPrank();

        uint256 minted = stableEngine.s_SenUSDMinted(admin);
        console.log("minted: %s", minted);

        minted = 100 ether;

        //MINT STABLE
        vm.startPrank(admin);
        _mintStableCoin(stableEngine, minted);
        vm.stopPrank();

        uint256 post_balanceTreasury_stable = stable.balanceOf(treasury);
        console.log("post_balanceTreasury_stable", post_balanceTreasury_stable);

        assertTrue(post_balanceTreasury_stable > prev_balanceTreasury_stable);

        //REVERT MINT ABOVE CAP
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(StableEngine.StableEngine__VaultMintCapReached.selector, 1000100000000000000000001)
        );
        stableEngine.mintSenUSD(vaultCap + 1);
        vm.stopPrank();

        //PRICE FELL 50%
        _updatePrice(wethOracle, stableEngine, ETH_USD_PRICE / 2);

        //BURN, Repays all his debt before getting liquidated
        uint256 borrowedMinted = stableEngine.s_SenUSDMinted(admin);
        uint256 cumInterest = stableEngine.getCompoundedInterestRate(admin, borrowedMinted);
        uint256 mintFee = borrowedMinted - stable.balanceOf(admin);
        getStableOnSecondaryMarket(address(stableEngine), stable, cumInterest - borrowedMinted + mintFee, admin);
        uint256 totalBurning = borrowedMinted + mintFee;
        vm.startPrank(admin);
        _repayStableCoin(stableEngine, borrowedMinted, totalBurning);
        vm.stopPrank();

        uint256 burn_FeeTreasury_stable = stable.balanceOf(treasury);

        assertTrue(
            burn_FeeTreasury_stable > post_balanceTreasury_stable,
            "burn_FeeTreasury_stable should be > post_balanceTreasury_stable"
        );

        uint256 newMinted = stableEngine.s_SenUSDMinted(admin);
        // console.log("newMinted: %s", newMinted);
        assertTrue(newMinted < minted, "newMinted should be < minted");
        uint256 newHealth2 = stableEngine.getHealthFactor(admin);
        console.log("newHealth: %s", newHealth2);

        vm.prank(admin);
        stableEngine.setLiquidator(admin, true);

        //REVERT CAN'T LIQUIDATE
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(StableEngine.StableEngine__HealthFactorOk.selector));
        stableEngine.liquidate(address(wethMock), admin, 1);
        vm.stopPrank();
    }

    function test_LiquidateUser() public {
        uint256 amount = 1 ether;
        user = address(3);

        //MINT COLLATERAL
        wethMock.mint(user, amount);
        stethMock.mint(user, amount);
        //log balances
        console.log("wethMock.balanceOf(user):  %s", wethMock.balanceOf(user));
        console.log("stethMock.balanceOf(user): %s", stethMock.balanceOf(user));

        //DEPOSIT COLLATERAL
        vm.startPrank(user);
        _depositCollateral(stableEngine, wethMock, amount);
        _depositCollateral(stableEngine, stethMock, amount / 2);
        vm.stopPrank();

        //MINT STABLE
        // uint dollar = oracle.getAmountPriced(amount, address(wethMock));
        // console.log("dollar: %s", dollar);
        uint256 dollar = stableEngine.getAccountCollateralValue(user);
        console.log("dollar: %s", dollar);
        dollar = stableEngine.getMaxMintableWithFee(user) - 10 ether; //otherwise breaks health factor, needs x2 overcollateralization
        vm.startPrank(user);
        _mintStableCoin(stableEngine, dollar);
        assertTrue(stableEngine.getHealthFactor(user) >= 1e18, "health factor should be >= 1e18");
        vm.stopPrank();

        console.log("LIQUIDATIONS HEALTH");
        console.log("healthFactor: %s", stableEngine.getHealthFactor(user));
        //PRICE FELL 50%
        _updatePrice(wethOracle, stableEngine, ETH_USD_PRICE / 2);
        console.log("healthFactor: %s", stableEngine.getHealthFactor(user));

        //LIQUIDATE
        vm.prank(admin);
        stableEngine.setLiquidator(liquidator, true);

        console.log("LIQUIDATE");
        console2.log("timestamp MINTED", stableEngine.getMintedLastTimestamp(user));

        vm.warp(block.timestamp + 1 days);

        uint256 prev_balanceTreasury_stable = stable.balanceOf(treasury);

        uint256 collateralTaken = oracle.getAmountPriced(amount / 2, address(wethMock));
        console.log("collateralTaken", collateralTaken);
        uint256 cumInterest = stableEngine.getCompoundedInterestRate(user, collateralTaken);
        uint256 liqFee = stableEngine.getLiqFee(cumInterest * LIQUIDATION_BONUS / 1e18);
        uint256 interestRateFee = cumInterest - collateralTaken;
        console.log("liqFee", liqFee);
        console.log("interestRateFee", interestRateFee);
        cumInterest += stableEngine.getLiqFee(cumInterest);
        getStableOnSecondaryMarket(address(stableEngine), stable, cumInterest, liquidator);

        vm.startPrank(liquidator);
        _liquidate(stableEngine, stable, wethMock, user, cumInterest, collateralTaken);
        vm.stopPrank();

        uint256 post_balanceTreasury_stable = stable.balanceOf(treasury);
        assertTrue(
            post_balanceTreasury_stable > prev_balanceTreasury_stable,
            "post_balanceTreasury_stable should be > prev_balanceTreasury_stable"
        );
        console.log("increase_balanceTreasury_stable", post_balanceTreasury_stable - prev_balanceTreasury_stable);
        console.log("expected increase              ", liqFee + interestRateFee);
        // assertTrue( (post_balanceTreasury_stable - prev_balanceTreasury_stable) == (liqFee + interestRateFee), "treasury increased by interest rate and liq fee");
    }

    function setupALiquidation() internal returns (uint256) {
        uint256 amount = 1e18;
        user = address(3);

        //MINT COLLATERAL
        wethMock.mint(user, amount);
        stethMock.mint(user, amount);
        //log balances
        console.log("wethMock.balanceOf(user):  %s", wethMock.balanceOf(user));
        console.log("stethMock.balanceOf(user): %s", stethMock.balanceOf(user));

        //DEPOSIT COLLATERAL
        vm.startPrank(user);
        _depositCollateral(stableEngine, wethMock, amount);
        _depositCollateral(stableEngine, stethMock, amount / 2);
        vm.stopPrank();

        // uint256 prev_balanceTreasury_stable = wethMock.balanceOf(treasury);
        // uint256 prev_balanceTreasury_stethMock = stethMock.balanceOf(treasury);

        //MINT STABLE
        // uint dollar = oracle.getAmountPriced(amount, address(wethMock));
        // console.log("dollar: %s", dollar);
        uint256 dollar = stableEngine.getAccountCollateralValue(user);
        console.log("dollar: %s", dollar);
        dollar /= 2; //otherwise breaks health factor, needs x2 overcollateralization
        vm.startPrank(user);
        _mintStableCoin(stableEngine, dollar);
        assertTrue(stableEngine.getHealthFactor(user) >= 1e18);
        vm.stopPrank();

        console.log("LIQUIDATIONS HEALTH");
        console.log("healthFactor: %s", stableEngine.getHealthFactor(user));
        //PRICE FELL 50%
        _updatePrice(wethOracle, stableEngine, ETH_USD_PRICE / 2);
        console.log("healthFactor: %s", stableEngine.getHealthFactor(user));
        uint256 dollarCollateral = stableEngine.getAccountCollateralValue(user);
        console.log("dollarCollateral: %s", dollarCollateral);
        return dollar / 2;
    }

    function test_RedeemFullCollateral() public {
        //MINT COLLATERAL
        uint256 amount = 1e18;
        user = address(3);
        wethMock.mint(user, amount);
        uint256 borrowed = 100e18;

        //DEPOSIT COLLATERAL
        vm.startPrank(user);

        wethMock.approve(address(stableEngine), amount);
        stableEngine.depositCollateral(address(wethMock), amount);

        //MINT STABLE
        stableEngine.mintSenUSD(borrowed);

        console.log("minted   : %s", stableEngine.s_SenUSDMinted(user));
        uint256 balance = stable.balanceOf(user);
        console.log("balanc1  : %s", balance);
        vm.stopPrank();

        //REDEEM COLLATERAL AND PAY INTEREST RATE FEES
        vm.warp(block.timestamp + 1 hours);

        uint256 borrowedMinted = stableEngine.s_SenUSDMinted(user);
        uint256 mintFee = borrowedMinted - balance;
        uint256 cumInterest = stableEngine.getCompoundedInterestRate(user, borrowedMinted);
        uint256 totalBurning = borrowedMinted + mintFee;
        console.log("borrowedMinted: %s", borrowedMinted);
        getStableOnSecondaryMarket(address(stableEngine), stable, cumInterest - borrowedMinted + mintFee, user);

        vm.startPrank(user);
        stable.approve(address(stableEngine), totalBurning);
        stableEngine.redeemCollateralForSenUSD(address(wethMock), amount, borrowedMinted);
        vm.stopPrank();

        console.log("minted   : %s", stableEngine.s_SenUSDMinted(user));
        console.log("balance s: %s", stable.balanceOf(user));
        console.log("balance w: %s", wethMock.balanceOf(user));
        console.log("eng bal W: %s", wethMock.balanceOf(address(stableEngine)));
        console.log("treas b S: %s", stable.balanceOf(treasury));
        console.log("user debt: %s", stableEngine.s_SenUSD_Debt(user));

        assertTrue(stableEngine.s_SenUSDMinted(user) == 0, "s_SenUSDMinted should be 0");
        assertTrue(stable.balanceOf(user) == 0, "stable.balanceOf(user) should be 0");
        assertTrue(wethMock.balanceOf(user) == amount, "wethMock.balanceOf(user) should be amount");
        assertTrue(stableEngine.s_SenUSD_Debt(user) == 0, "s_SenUSD_Debt(user) should be 0");
    }

    function test_FeesMint() public {
        uint256 amount = 1e18;
        user = address(3);

        //MINT COLLATERAL
        wethMock.mint(user, amount);
        stethMock.mint(user, amount);
        //log balances
        console.log("wethMock.balanceOf(user):  %s", wethMock.balanceOf(user));
        console.log("stethMock.balanceOf(user): %s", stethMock.balanceOf(user));

        //DEPOSIT COLLATERAL
        vm.startPrank(user);
        _depositCollateral(stableEngine, wethMock, amount);
        _depositCollateral(stableEngine, stethMock, amount / 2);
        vm.stopPrank();

        uint256 time1 = stableEngine.getMintedLastTimestamp(user);
        console.log("time1: %s", time1);
        assertTrue(time1 == 0, "time1 should be 0");

        vm.warp(block.timestamp + 1 days);

        //MINT STABLE
        // uint dollar = oracle.getAmountPriced(amount, address(wethMock));
        // console.log("dollar: %s", dollar);
        uint256 dollar = stableEngine.getMaxMintable(user) - 10 ether;
        uint256 mintedMinusFee = stableEngine.calculateMintWithFee(dollar);
        console.log("dollar: %s", dollar);
        console.log("mintedMinusFee", mintedMinusFee);
        vm.startPrank(user);
        _mintStableCoin(stableEngine, dollar);
        assertTrue(stableEngine.getHealthFactor(user) >= 1e18);
        vm.stopPrank();

        console.log("stable.balanceOf(user)", stable.balanceOf(user));
        console.log("stable.balanceOf(treasury)", stable.balanceOf(treasury));
        uint256 time2 = stableEngine.getMintedLastTimestamp(user);
        console.log("time2: %s", time2);
        assertTrue(time2 > time1, "time2 should be > time1");
        assertTrue(stableEngine.s_SenUSDMinted(user) == dollar, "s_SenUSDMinted should be == amount wanted");
        assertTrue(stable.balanceOf(user) == mintedMinusFee, "fee calculated");
        assertTrue(stable.balanceOf(treasury) == dollar - mintedMinusFee, "fee to treasury");
    }

    function test_LiquidateAllCollateral() public {
        uint256 amount = 1e18;
        user = address(3);

        //MINT COLLATERAL
        wethMock.mint(user, amount);

        //DEPOSIT COLLATERAL
        vm.startPrank(user);
        _depositCollateral(stableEngine, wethMock, amount);
        vm.stopPrank();

        //log eth spot price
        uint256 spot = oracle.getSpotPrice(address(wethMock));
        console.log("spot: %s", spot);

        //max debt
        uint256 maxDebt = stableEngine.getMaxDebt(user);
        console.log("maxDebt: %s", maxDebt);
        assertTrue(maxDebt == 1000 ether, "maxDebt should be 1000 ether");

        //max mintable
        uint256 maxMintable = stableEngine.getMaxMintable(user);
        console.log("maxMintable", maxMintable);
        assertTrue(maxMintable == 1000 ether, "maxMintable should be 1000 ether");

        //max mintable with fee
        uint256 maxMintableWithFee = stableEngine.getMaxMintableWithFee(user);
        console.log("maxMintableWithFee", maxMintableWithFee);
        assertTrue(maxMintableWithFee == 990 ether, "maxMintableWithFee should be 990 ether");

        uint256 dollar = maxDebt - 1 ether;

        vm.startPrank(user);
        _mintStableCoin(stableEngine, dollar);
        vm.stopPrank();

        uint256 hf1 = stableEngine.getHealthFactor(user);
        console.log("hf1: %s", hf1);

        uint256 liqPrice = stableEngine.getLiquidationPrice(user);
        console.log("liqPrice: %s", liqPrice);
        assertTrue(liqPrice == 1998000000000000000000, "liq price is not 1998$");

        //make price fall to liqPrice
        _updatePrice(wethOracle, stableEngine, 1);
        vm.warp(block.timestamp + 7 days);

        uint256 hf2 = stableEngine.getHealthFactor(user);
        console.log("hf2: %s", hf2);

        //assert health factor got worse
        assertTrue(hf2 < hf1, "hf2 should be worse than hf1");

        //LIQUIDATE
        uint256 debtToCover = stableEngine.getDebtToCover(user);
        console.log("debtToCover: %s", debtToCover);

        vm.prank(address(stableEngine));
        stable.mint(liquidator, debtToCover);

        vm.prank(admin);
        stableEngine.setLiquidator(liquidator, true);

        vm.startPrank(liquidator);
        stable.approve(address(stableEngine), debtToCover);
        stableEngine.liquidate(address(wethMock), user, debtToCover + stableEngine.getLiqFee(debtToCover));
        vm.stopPrank();

        uint256 amountWETHLiquidator = wethMock.balanceOf(liquidator);
        console.log("amountWETHLiquidator: %s", amountWETHLiquidator);
        assertTrue(amountWETHLiquidator == amount, "did not get all collateral from user");
        assertTrue(
            stableEngine.getCollateralBalanceOfUser(user, address(wethMock)) == 0, "user should have 0 collateral"
        );
    }

    function test_FeesBurn() public {
        uint256 amount = 1e18;
        user = address(3);

        //MINT COLLATERAL
        wethMock.mint(user, amount);
        stethMock.mint(user, amount);
        //log balances
        console.log("wethMock.balanceOf(user):  %s", wethMock.balanceOf(user));

        //DEPOSIT COLLATERAL
        vm.startPrank(user);
        _depositCollateral(stableEngine, wethMock, amount);
        vm.stopPrank();

        uint256 time1 = stableEngine.getMintedLastTimestamp(user);
        console.log("time1: %s", time1);
        assertTrue(time1 == 0, "time1 should be 0");

        vm.warp(block.timestamp + 1 days);

        uint256 hf1 = stableEngine.getHealthFactor(user);
        console.log("hf1: %s", hf1);
        //MINT STABLE
        // uint dollar = oracle.getAmountPriced(amount, address(wethMock));
        // console.log("dollar: %s", dollar);
        uint256 dollar = stableEngine.getAccountCollateralValue(user);
        console.log("dollar: %s", dollar);
        dollar = 900 ether; //otherwise breaks health factor, needs x2 overcollateralization
        vm.startPrank(user);
        _mintStableCoin(stableEngine, dollar);
        assertTrue(stableEngine.getHealthFactor(user) >= 1e18, "health factor should be >= 1e18");
        vm.stopPrank();

        uint256 time2 = stableEngine.getMintedLastTimestamp(user);
        console.log("time2: %s", time2);
        assertTrue(time2 > time1, "time2 should be > time1");

        uint256 treasurybalance_old = stable.balanceOf(treasury);
        console.log("user debt before time", stableEngine.getDebtToCover(user));

        hf1 = stableEngine.getHealthFactor(user);
        vm.warp(block.timestamp + 5 days);
        uint256 hf2 = stableEngine.getHealthFactor(user);

        //log hf, and assertTrue hf2 > hf1
        console.log("hf1: %s", hf1);
        console.log("hf2: %s", hf2);
        assertTrue(hf2 < hf1, "hf2 should be worse because of compounded interest rate");

        //BURN
        console.log("user debt after time", stableEngine.getDebtToCover(user));
        uint256 borrowedMinted = stableEngine.s_SenUSD_Debt(user);
        uint256 cumInterest = stableEngine.getCompoundedInterestRate(user, borrowedMinted);
        uint256 mintFee = borrowedMinted - stable.balanceOf(user);
        getStableOnSecondaryMarket(address(stableEngine), stable, cumInterest - borrowedMinted + mintFee, user);
        uint256 totalBurning = borrowedMinted + mintFee;

        vm.startPrank(user);
        _repayStableCoin(stableEngine, borrowedMinted, totalBurning);
        vm.stopPrank();

        uint256 treasurybalance_new = stable.balanceOf(treasury);
        console.log("treasury stable balance: %s", treasurybalance_new);
        assertTrue(treasurybalance_new > treasurybalance_old, "treasurybalance_new should be > treasurybalance_old");
    }

    function test_FeesMintMintBurn() public {
        uint256 amount = 1e18;
        user = address(3);
        uint256 dollar = 100 ether; //100$ stablecoin

        //MINT COLLATERAL
        wethMock.mint(user, amount);
        //log balances
        console.log("wethMock.balanceOf(user):  %s", wethMock.balanceOf(user));

        //DEPOSIT COLLATERAL
        vm.startPrank(user);
        _depositCollateral(stableEngine, wethMock, amount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        //MINT STABLE
        // uint dollar = oracle.getAmountPriced(amount, address(wethMock));
        // console.log("dollar: %s", dollar);
        vm.startPrank(user);
        _mintStableCoin(stableEngine, dollar);
        assertTrue(stableEngine.getHealthFactor(user) >= 1e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days);

        //MINT STABLE
        // uint dollar = oracle.getAmountPriced(amount, address(wethMock));
        // console.log("dollar: %s", dollar);
        vm.startPrank(user);
        _mintStableCoin(stableEngine, dollar);
        assertTrue(stableEngine.getHealthFactor(user) >= 1e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        //BURN
        uint256 borrowedMinted = stableEngine.s_SenUSDMinted(user);
        console.log("borrowedMinted: %s", borrowedMinted);
        uint256 cumInterest = stableEngine.getCompoundedInterestRate(user, borrowedMinted);
        console.log("cumInterest   : %s", cumInterest);
        console.log("stable.balance: %s", stable.balanceOf(user));
        uint256 mintFee = borrowedMinted - stable.balanceOf(user);
        console.log("mintFee       : %s", mintFee);
        getStableOnSecondaryMarket(address(stableEngine), stable, cumInterest - borrowedMinted + mintFee, user);
        uint256 totalBurning = cumInterest + mintFee;

        vm.startPrank(user);
        _repayStableCoin(stableEngine, borrowedMinted, totalBurning);
        vm.stopPrank();

        uint256 treasurybalance_new = stable.balanceOf(treasury);
        console.log("treasury stable balance: %s", treasurybalance_new);
        console.log("user stable balance    : %s", stable.balanceOf(user));
    }

    function test_InterestAccrueOnMint() public {
        vm.prank(admin);
        stableEngine.setInterestRate(10 * 1e27); //10% interest rate
        uint256 amount = 1e18;
        user = address(3);
        uint256 dollar = 100 ether; //100$ stablecoin

        //MINT COLLATERAL
        wethMock.mint(user, amount);
        //log balances
        console.log("wethMock.balanceOf(user):  %s", wethMock.balanceOf(user));

        //DEPOSIT COLLATERAL
        vm.startPrank(user);
        _depositCollateral(stableEngine, wethMock, amount);
        vm.stopPrank();

        //MINT STABLE
        // uint dollar = oracle.getAmountPriced(amount, address(wethMock));
        // console.log("dollar: %s", dollar);
        vm.startPrank(user);
        _mintStableCoin(stableEngine, dollar);
        vm.stopPrank();

        console.log("mintedDebt", stableEngine.s_SenUSDMinted(user));

        vm.warp(block.timestamp + 7 days);

        vm.startPrank(user);
        _mintStableCoin(stableEngine, 1 ether);
        vm.stopPrank();

        console.log("mintedDebt", stableEngine.s_SenUSDMinted(user));
    }

    function test_BurnAfterMintingDebt() public {
        test_InterestAccrueOnMint();
    }

    function test_getEngineInfo() public {
        (
            string memory _name,
            uint256 totalSenUSDBorrowed,
            uint256 TVL,
            uint256 interestRate,
            uint256 senUSDLeftToMin,
            uint256 LTV
        ) = stableEngine.getEngineInfo();
        console.log("ltv", LTV);
    }

    function test_liqPrice() public {
        uint256 totalSenUSDDebt = 1342 ether;
        uint256 nominalCollateral = 3.24 ether;
        uint256 ltv = 0.68 ether;

        uint256 price = (totalSenUSDDebt * 1e18) / (ltv) * 1e18 / nominalCollateral;
        console.log("price", price); //= 609.1
    }

    function test_fullLiquidationValues() public {
        uint256 borrowing = 990 ether;
        uint256 collateral = 1 ether;
        wethMock.mint(user, collateral);

        vm.startPrank(user);
        _depositCollateral(stableEngine, wethMock, collateral);
        vm.stopPrank();

        vm.startPrank(user);
        _mintStableCoin(stableEngine, borrowing);
        vm.stopPrank();

        uint256 liqPrice = stableEngine.getLiquidationPrice(user);
        //log collateral price
        console.log("$eth price", oracle.getSpotPrice(address(wethMock)));
        //log user liq price
        console.log("$eth liq  ", liqPrice);

        //log debt
        console.log("userA debt", stableEngine.getDebtToCover(user));
        // log collateral value
        console.log("userA $eth", stableEngine.getAccountCollateralValue(user));

        //make price fall to liquidate
        _updatePrice(wethOracle, stableEngine, int256(liqPrice / 1e10));

        //log new user account info
        (uint256 totalMinted, uint256 collateralValueInUsd, uint256 totalDebt,, uint256 hf) =
            stableEngine.getAccountInformation(user);
        console.log("userA $debt", totalDebt);
        console.log("userA $eth", collateralValueInUsd);
        console.log("userA Health", hf);

        uint256 totalSenUSD = totalDebt + stableEngine.getLiqFee(totalDebt);

        address userB = address(10);
        vm.prank(admin);
        stableEngine.setLiquidator(userB, true);
        //give userB senUSD to liquidate userA
        vm.prank(address(stableEngine));
        stable.mint(userB, totalSenUSD);

        console.log("senUSD balance userB", stable.balanceOf(userB));

        uint256 beforeUserWeth = wethMock.balanceOf(user);
        vm.startPrank(userB);
        stable.approve(address(stableEngine), totalSenUSD);
        stableEngine.liquidate(address(wethMock), user, totalMinted);
        vm.stopPrank();
        uint256 afterUserWeth = wethMock.balanceOf(user);

        (uint256 totalSenUSDMinted2, uint256 collateralValueInUsd2, uint256 totalDebt2, uint256 liqPrice2, uint256 hf2)
        = stableEngine.getAccountInformation(user);
        console.log("userA $debt", totalDebt2);
        console.log("userA $eth", collateralValueInUsd2);
        console.log("userA Health", hf2);
        console.log("userA minted", totalSenUSDMinted2);
        console.log("userA liqPrice", liqPrice2);
        console.log("userA balance wallet senUSD", stable.balanceOf(user));

        uint256 userB_eth = wethMock.balanceOf(userB);
        console.log("userB Eth", userB_eth);
        console.log("userB $eth", oracle.getAmountPriced(userB_eth, address(wethMock)));
        console.log("userB senUsd", stable.balanceOf(userB));
    }

    function test_partialLiquidationValues() public {
        uint256 borrowing = 500 ether;
        uint256 collateral = 1 ether;
        wethMock.mint(user, collateral);

        vm.startPrank(user);
        _depositCollateral(stableEngine, wethMock, collateral);
        vm.stopPrank();

        vm.startPrank(user);
        _mintStableCoin(stableEngine, borrowing);
        vm.stopPrank();

        uint256 liqPrice = stableEngine.getLiquidationPrice(user);
        //log collateral price
        console.log("$eth price", oracle.getSpotPrice(address(wethMock)));
        //log user liq price
        console.log("$eth liq  ", liqPrice);

        //log debt
        console.log("userA debt", stableEngine.getDebtToCover(user));
        // log collateral value
        console.log("userA $eth", stableEngine.getAccountCollateralValue(user));

        //make price fall to liquidate
        _updatePrice(wethOracle, stableEngine, int256(liqPrice / 1e10));

        //log new user account info
        (uint256 totalMinted, uint256 collateralValueInUsd, uint256 totalDebt,, uint256 hf) =
            stableEngine.getAccountInformation(user);
        totalMinted = 100 ether;
        totalDebt = stableEngine.getCompoundedInterestRate(user, totalMinted);
        console.log("userA $debt", totalDebt);
        console.log("userA $eth", collateralValueInUsd);
        console.log("userA Health", hf);

        uint256 totalSenUSD = totalDebt + stableEngine.getLiqFee(totalDebt);

        address userB = address(10);
        vm.prank(admin);
        stableEngine.setLiquidator(userB, true);

        //give userB senUSD to liquidate userA
        vm.prank(address(stableEngine));
        stable.mint(userB, totalSenUSD);

        console.log("senUSD balance userB", stable.balanceOf(userB));

        uint256 beforeUserWeth = wethMock.balanceOf(user);
        vm.startPrank(userB);
        stable.approve(address(stableEngine), totalSenUSD);
        stableEngine.liquidate(address(wethMock), user, totalMinted);
        vm.stopPrank();
        uint256 afterUserWeth = wethMock.balanceOf(user);

        (uint256 totalSenUSDMinted2, uint256 collateralValueInUsd2, uint256 totalDebt2, uint256 liqPrice2, uint256 hf2)
        = stableEngine.getAccountInformation(user);
        console.log("userA $debt", totalDebt2);
        console.log("userA $eth", collateralValueInUsd2);
        console.log("userA Health", hf2);
        console.log("userA minted", totalSenUSDMinted2);
        console.log("userA liqPrice", liqPrice2);
        console.log("userA balance wallet senUSD", stable.balanceOf(user));

        uint256 userB_eth = wethMock.balanceOf(userB);
        console.log("userB Eth", userB_eth);
        console.log("userB $eth", oracle.getAmountPriced(userB_eth, address(wethMock)));
        console.log("userB senUsd", stable.balanceOf(userB));
    }
}
