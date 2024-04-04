// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../src/StableCoin.sol";
import "../src/libs/IERC20.sol";

contract TokenTestL1 is Test {
    address srcToken = 0xe14058B1c3def306e2cb37535647A04De03Db092;
    address dstToken = 0x95401dc811bb5740090279Ba06cfA8fcF6113778;
    StableCoin token;
    address USER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        token = StableCoin(srcToken);
    }

    function testCheckBalance() public {
        console.log("Token Name", token.name());
        console.log("Token Balance", token.balanceOf(USER));
        assertTrue(token.balanceOf(USER) > 0);
    }
}
