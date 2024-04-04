import os
from decouple import config
import time

#set the environment variables
rpcL1 = config("ETHEREUM_RPC_URL")
rpcL2 = config("ARBITRUM_RPC_URL")
pk = config("LOCAL_PRIVATE_KEY")
cmdL1 = "anvil --accounts 10 --balance 1000 --fork-url " + rpcL1 + " --fork-block-number 16678250"
cmdL2 = "anvil --accounts 10 --balance 1000 --fork-url " + rpcL2 + " --fork-block-number 63160273 -p 8546"

#open terminal and run the command
os.system("gnome-terminal -e 'bash -c \"" + cmdL1 + "; exec bash\"'")
os.system("gnome-terminal -e 'bash -c \"" + cmdL2 + "; exec bash\"'")

time.sleep(5)
print("Anvil is running\n")
print("Deploying contracts...")
localRpcL1 = config("LOCAL_RPC_URL1")
localRpcL2 = config("LOCAL_RPC_URL2")

#Deploy TokenScript
contractName = "TokenScript"

cmdDeployL1 = "forge script " + contractName + "L1" + " --broadcast --rpc-url " + localRpcL1 + " --private-key " + pk + " -vv --legacy"
os.system(cmdDeployL1)
print("Token deployed on Layer 1\n")

cmdDeployL2 = "forge script " + contractName + "L2" + " --broadcast --rpc-url " + localRpcL2 + " --private-key " + pk + " -vv --legacy"
os.system(cmdDeployL2)
print("Token deployed on Layer 2\n")

time.sleep(5)

#Deploy TokenBridgeScript
contractName = "TokenBridgeScript"
cmdDeployL1 = "forge script " + contractName + "L1" + " --broadcast --rpc-url " + localRpcL1 + " --private-key " + pk + " -vv --legacy"
cmdDeployL2 = "forge script " + contractName + "L2" + " --broadcast --rpc-url " + localRpcL2 + " --private-key " + pk + " -vv --legacy"
os.system(cmdDeployL1)
print("Token Bridged from Layer 1\n")
os.system(cmdDeployL2)
print("Token Bridged from Layer 2\n")

time.sleep(5)

#Test Token Balance
print("Testing Token Balance...")
contractName = "TokenTest"
cmdTestL1 = "forge test --match-contract " + contractName + "L1" + " --fork-url " + localRpcL1 + " -vv"
cmdTestL2 = "forge test --match-contract " + contractName + "L2" + " --fork-url " + localRpcL2 + " -vv"
os.system(cmdTestL1)
os.system(cmdTestL2)
print("Token Balance Test done!\n")

