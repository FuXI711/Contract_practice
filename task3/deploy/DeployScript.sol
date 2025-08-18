// script/Deploy.s.sol
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/MyERC20GasOpt.sol";

contract DeployScript is Script {
    function run() external {
        // 从环境变量读取配置
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory network = vm.envString("NETWORK");

        // 网络特定配置
        string memory name;
        if (keccak256(bytes(network)) == keccak256(bytes("mainnet"))) {
            name = "MainnetToken";
        } else if (keccak256(bytes(network)) == keccak256(bytes("optimism"))) {
            name = "OptimismToken";
        } else {
            name = "TestToken";
        }

        // 开始广播交易
        vm.startBroadcast(deployerKey);
        MyERC20GasOpt token = new MyERC20GasOpt(name, "TKN");
        console.log("%s deployed at: %s", name, address(token));
        vm.stopBroadcast();
    }
}