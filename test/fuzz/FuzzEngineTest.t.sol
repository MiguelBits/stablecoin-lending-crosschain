pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {Setup} from "../Setup.t.sol";

import {StableCoin} from "../../src/StableCoin.sol";
import {StableEngine} from "../../src/StableEngine.sol";
import {SenecaEngine} from "../../src/engines/SenecaEngine.sol";
import {Oracle} from "../../src/oracles/Oracle.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract FuzzEngineTest is Test, Setup {
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

    function testFuzz_Deposit(uint256 _amount, address _user) public {
        vm.assume(_amount > 0);
        vm.assume(_amount < 10000000000 ether);
        vm.assume(_user != address(0));
        wethMock.mint(_user, _amount);
        vm.startPrank(_user);
        _depositCollateral(stableEngine, wethMock, _amount);
        vm.stopPrank();
    }

    function testFuzz_Mint(address _user) public {

        uint256 collateral = 10000000000 ether;
        uint256 _amount = 10000 ether;
        vm.assume(_user != address(0));
        
        wethMock.mint(_user, collateral);
        vm.startPrank(_user);
        _depositCollateral(stableEngine, wethMock, collateral);

        for(uint i = 0; i < 10; i++) {
            stableEngine.mintSenUSD(_amount);
        }

        stableEngine.mintSenUSD(_amount);
        vm.stopPrank();
    }

    // function testFuzz_Liquidate(uint _amount, address _user, address _liquidator, uint _amountStable, uint _amountWei) public {
    //     vm.assume(_amount > 0);
    //     vm.assume(_user != address(0));
    //     vm.assume(_liquidator != address(0));
    //     vm.assume(_amount < 10000000000 ether);

    //     wethMock.mint(_user, _amount);
    //     wethMock.mint(_liquidator, _amount);

    //     vm.startPrank(_user);
    //     _depositCollateral(stableEngine, wethMock, _amount);
    //     vm.stopPrank();

    //     //PRICE FELL 50%
    //     _updatePrice(wethOracle, stableEngine, ETH_USD_PRICE / 2);

    //     vm.startPrank(_liquidator);
    //     stableEngine.flashLiquidate(address(wethMock), _amountWei, _user, _amountStable);
    //     vm.stopPrank();
    // }
}
