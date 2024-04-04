// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {StableCoin} from "../../src/StableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Setup} from "../Setup.t.sol";
import {StableEngine} from "../../src/StableEngine.sol";

contract CoinTest is StdCheats, Test, Setup {
    StableCoin SenUSD;
    address engine;
    StableEngine _engine;

    function setUp() public {
        (SenUSD, _engine,,,,,) = deploy();
        engine = address(_engine);
    }

    function testMustMintMoreThanZero() public {
        vm.prank(engine);
        vm.expectRevert();
        SenUSD.mint(address(this), 0);
    }

    function testMustBurnMoreThanZero() public {
        vm.startPrank(engine);
        SenUSD.mint(address(this), 100);
        vm.expectRevert();
        SenUSD.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(engine);
        SenUSD.mint(address(this), 100);
        vm.expectRevert();
        SenUSD.burn(101);
        vm.stopPrank();
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(engine);
        vm.expectRevert();
        SenUSD.mint(address(0), 100);
        vm.stopPrank();
    }
}
