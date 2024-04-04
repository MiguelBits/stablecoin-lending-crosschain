// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../../src/StableCoin.sol";

import "../../lib/solidity-examples/contracts/mocks/LZEndpointMock.sol";
import "../../lib/solidity-examples/contracts/token/oft/v2/ICommonOFT.sol";

contract TokenBridgeScriptL2 is Script {
    address srcToken = 0xe14058B1c3def306e2cb37535647A04De03Db092;
    address dstToken = 0x95401dc811bb5740090279Ba06cfA8fcF6113778;

    address EthMainnetLzEndpoint = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675; //TODO
    uint16 EthMainnetChainId = 101;
    address ArbLzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
    uint16 ArbChainId = 110;
    uint256 GAS = 1 ether;
    uint256 amount = 1e9;

    function run() public {
        vm.startBroadcast();

        bytes32 _toAddress = bytes32(abi.encodePacked(msg.sender));
        bytes memory _adapterParams = new bytes(0);

        // Deploy the token on the mainnet
        StableCoin token = StableCoin(dstToken);
        token.allowEngineContract(msg.sender);
        token.mint(msg.sender, 1 ether);

        //set trusted remote
        // bytes memory dstPath = abi.encodePacked(dstToken,srcToken);
        bytes memory srcPath = abi.encodePacked(srcToken, dstToken);
        token.setTrustedRemote(EthMainnetChainId, srcPath);
        console.log("Trusted remote set");

        // (GAS, ) = token.estimateSendFee(ArbChainId, _toAddress, amount, false, _adapterParams);

        // send some tokens on the mainnet
        token.approve(address(token), token.totalSupply());
        token.sendFrom{value: GAS}(
            msg.sender,
            EthMainnetChainId,
            bytes32(abi.encodePacked(msg.sender)),
            amount,
            0, //minAmount
            ICommonOFT.LzCallParams(payable(msg.sender), address(0), new bytes(0))
        );

        console.log("Tokens sent to Arb");
        console2.log("Token Balance", token.balanceOf(msg.sender));
        vm.stopBroadcast();
    }
}
