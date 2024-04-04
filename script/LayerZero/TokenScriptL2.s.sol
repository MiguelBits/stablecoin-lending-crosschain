// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../../src/StableCoin.sol";

import "../../lib/solidity-examples/contracts/mocks/LZEndpointMock.sol";
import "../../lib/solidity-examples/contracts/token/oft/v2/ICommonOFT.sol";

contract TokenScriptL2 is Script {
    // address EthMainnetLzEndpoint = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675; //TODO
    // uint16 EthMainnetChainId = 101;
    address ArbLzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
    // uint16 ArbChainId = 110;

    function run() public returns (StableCoin token2) {
        vm.startBroadcast();

        // Deploy the token on the mainnet
        token2 = new StableCoin(ArbLzEndpoint);
        console.log("Token deployed on arbitrum: ", address(token2));

        vm.stopBroadcast();
    }
}
