forge install LayerZero-Labs/solidity-examples --no-commit

cd lib/solidity-examples

npx hardhat compile

framework.py is a script that runs on linux terminal to fork multiple chains and test out the layer zero cross chain features

Radiant Engine -> 4626 vault that implements 1155 tokens where the mint id corresponds to the Radiant Token deposited, this is done to allow wrapping radiant tokens to accrue their rebases.

This is a stable that functions like DAI where a collateral ratio must be met to keep on minting the stable coin, and protocol will liquidate a user to maintain protocol requirements
