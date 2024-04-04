// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {Oracle} from "../../src/oracles/Oracle.sol";
import {RadiantEngine, ERC20, StableCoin} from "../../src/engines/RadiantEngine.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Setup} from "../Setup.t.sol";

contract RadiantEngineTest is StdCheats, Test, Setup {
    Oracle oracle;
    RadiantEngine radiantEngine;
    StableCoin stable;
    address rToken = 0x48a29E756CC1C097388f3B2f3b570ED270423b3d; // rUSDC
    address usdcOracle = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3; // usdc oracle chainlink
    address WHALE = 0xA0076833d8316521E3ba4628AD84de11830aa813; //rToken whale

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        (stable, radiantEngine, oracle,,,,) = deployRadiant();

        vm.prank(radiantEngine.owner());
        radiantEngine.addRadiantToken(ERC20(rToken));

        vm.prank(oracle.owner());
        oracle.addAsset(rToken, usdcOracle, 1e6, 1e8);
        console.log("rToken spot", oracle.getSpotPrice(rToken));

        assertTrue(radiantEngine.radiantTokenAddresses(rToken) == 1, "radiant token not added1");
        assertTrue(radiantEngine.radiantTokenIds(1) == ERC20(rToken), "radiant token not added2");
    }

    ///////////////////////////////////
    //  Radiant Engine Tests         //
    ///////////////////////////////////

    function testDepositRadiant() public {
        uint256 amount = 100e6;
        
        vm.startPrank(WHALE);
        ERC20(rToken).approve(address(radiantEngine), amount);
        radiantEngine.depositCollateral(rToken, amount);
        vm.stopPrank();

        console.log("balance", ERC20(rToken).balanceOf(WHALE));
        console.log("balance", radiantEngine.balanceOf(WHALE, radiantEngine.currentTokenId()));

        uint bal = radiantEngine.getCollateralBalanceOfUser(WHALE, rToken);
        console.log("balance", bal);

        uint256 value = radiantEngine.getAccountCollateralValue(WHALE);
        console.log("value", value); //100$
    }

    function testMintSenUSDDepositRadiant() public {
        uint256 amount = 100e6;
        uint256 minted = 10 ether;
        console.log("balance", ERC20(rToken).balanceOf(WHALE));

        vm.startPrank(WHALE);
        ERC20(rToken).approve(address(radiantEngine), amount);
        radiantEngine.depositCollateral(rToken, amount);
        radiantEngine.mintSenUSD(minted);
        vm.stopPrank();

        console.log("balance r", ERC20(rToken).balanceOf(WHALE));
        console.log("balance t", radiantEngine.balanceOf(WHALE, radiantEngine.currentTokenId()));
        console.log("balance s", radiantEngine.sen_stable().balanceOf(WHALE));
    }

    function testMintMintRadiant() public {
        testMintSenUSDDepositRadiant();
        testMintSenUSDDepositRadiant();
    }

    function testAccountCollateralValue() public {
        testMintSenUSDDepositRadiant();
        uint256 value_beforeRebase = radiantEngine.getAccountCollateralValue(WHALE);
        console.log("value_beforeRebase", value_beforeRebase);

        vm.startPrank(WHALE);
        ERC20(rToken).transfer(address(radiantEngine), 100e6);
        vm.stopPrank();

        uint256 value_afterRebase = radiantEngine.getAccountCollateralValue(WHALE);
        console.log("value_afterRebase ", value_afterRebase);

        assertTrue(value_afterRebase > value_beforeRebase, "value not increased");
    }

    function testRedeemRadiantFromSenUSD() public {
        testMintSenUSDDepositRadiant();
        uint256 amount = 100e6;
        address SENUSD = address(radiantEngine.sen_stable());
        uint256 minted = ERC20(SENUSD).balanceOf(WHALE);
        console.log("balance r", ERC20(rToken).balanceOf(WHALE));
        console.log("balance s", ERC20(SENUSD).balanceOf(WHALE));
        uint256 prevBalance = ERC20(rToken).balanceOf(WHALE);

        vm.warp(block.timestamp + 1 days);

        uint256 borrowedMinted = radiantEngine.s_SenUSDMinted(WHALE);
        uint256 cumInterest = radiantEngine.getCompoundedInterestRate(WHALE, minted);
        uint256 mintFee = borrowedMinted - prevBalance;
        getStableOnSecondaryMarket(address(radiantEngine), stable, cumInterest - minted + mintFee, WHALE);
        uint256 totalBurning = borrowedMinted + mintFee;

        vm.startPrank(WHALE);
        ERC20(SENUSD).approve(address(radiantEngine), totalBurning);
        radiantEngine.redeemCollateralForSenUSD(rToken, amount, borrowedMinted);
        vm.stopPrank();

        console.log("balance r", ERC20(rToken).balanceOf(WHALE));
        console.log("balance s", ERC20(SENUSD).balanceOf(WHALE));
    }

    function test_LiqPrice() public {
        testMintSenUSDDepositRadiant();

        uint256 liqPrice = radiantEngine.getLiquidationPrice(WHALE);
        console.log("liqPrice", liqPrice);
    }

    function test_Liquidation() public {
        testMintSenUSDDepositRadiant();

        uint256 debt = radiantEngine.getDebtToCover(WHALE);
        console.log("debt", debt);

        vm.prank(admin);
        radiantEngine.setInterestRate(100e27);

        vm.warp(block.timestamp + 3 days);

        uint256 value_beforeRebase = radiantEngine.getAccountCollateralValue(WHALE);
        console.log("value_beforeRebase ", value_beforeRebase);

        vm.startPrank(WHALE);
        ERC20(rToken).transfer(address(radiantEngine), 10e6);
        vm.stopPrank();

        uint256 liqPrice = radiantEngine.getLiquidationPrice(WHALE);
        console.log("liqPrice", liqPrice);

        uint256 value_afterRebase = radiantEngine.getAccountCollateralValue(WHALE);
        console.log("value_afterRebase ", value_afterRebase);

        assertTrue(value_afterRebase > value_beforeRebase, "value not increased");

        //send to liquidation by compounding debt
        vm.warp(block.timestamp + 50 days);

        //log debt
        debt = radiantEngine.getDebtToCover(WHALE);
        console.log("debt", debt);

        //liquidate
        uint256 liqFee = radiantEngine.getLiqFee(debt * LIQUIDATION_BONUS / 1e18);
        vm.prank(address(radiantEngine));
        stable.mint(admin, debt + liqFee);

        //log health factor
        uint256 healthFactor = radiantEngine.getHealthFactor(WHALE);
        console.log("healthFactor", healthFactor);

        vm.startPrank(admin);
        radiantEngine.setLiquidator(admin, true);
        stable.approve(address(radiantEngine), debt + liqFee);
        radiantEngine.liquidate(rToken, WHALE, debt);
        vm.stopPrank();

        //log debt
        debt = radiantEngine.getDebtToCover(WHALE);
        console.log("debt", debt);

        //log admin bonus collateral
        uint256 adminBonusCollateral = ERC20(rToken).balanceOf(admin);
        console.log("adminBonusCollateral", adminBonusCollateral);

        //log whale collateral
        uint256 whaleCollateral = ERC20(rToken).balanceOf(WHALE);
        console.log("whaleCollateral", whaleCollateral);
    }

    function test_InterestPercent() public {
        vm.prank(admin);
        radiantEngine.setInterestRate(365e27);

        testMintSenUSDDepositRadiant();

        uint256 debt0 = radiantEngine.getDebtToCover(WHALE);
        console.log("debt0", debt0);

        vm.warp(block.timestamp + 1);

        uint256 debt1 = radiantEngine.getDebtToCover(WHALE);
        console.log("debt1", debt1);

        uint256 onePercent = debt0 * 0.00001159 ether / 1e18;
        console.log("onePercent", onePercent);
        console.log("debt1 - debt0", debt1 - debt0);
        // 115900000000000
        // 115740740740741
        // assertTrue(debt1 == debt0 + onePercent, "debt not increased by 1%");
    }
}
