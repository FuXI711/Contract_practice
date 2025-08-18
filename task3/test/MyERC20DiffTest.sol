// test/MyERC20_DiffTest.sol
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MyERC20.sol";
import "../src/MyERC20GasOpt.sol"; // 假设这是优化后的版本

contract MyERC20DiffTest is Test {
    // 声明两个版本的合约
    MyERC20 legacyToken;
    MyERC20GasOpt optimizedToken;
    
    address owner = address(0x1);
    address userA = address(0x2);
    address userB = address(0x3);

    function setUp() public {
        // 同时部署两个版本的合约
        vm.startPrank(owner);
        legacyToken = new MyERC20("Legacy", "LGT");
        optimizedToken = new MyERC20GasOpt("Optimized", "OPT");
        vm.stopPrank();

        // 为两个版本初始化相同状态（以 owner 身份）
        vm.startPrank(owner);
        legacyToken.mint(userA, 1000 * 10**legacyToken.decimals());
        optimizedToken.mint(userA, 1000 * 10**optimizedToken.decimals());
        vm.stopPrank();
    }

    // 转账功能差分测试
    function testDiff_Transfer(uint128 amount) public {
        // 公共过滤条件
        vm.assume(amount > 0);
        vm.assume(amount <= 500 * 10**legacyToken.decimals());

        // 记录初始状态
        uint256 legacyStartBalance = legacyToken.balanceOf(userA);
        uint256 optimizedStartBalance = optimizedToken.balanceOf(userA);

        // 执行旧版本转账
        vm.prank(userA);
        legacyToken.transfer(userB, amount);

        // 执行新版本转账
        vm.prank(userA);
        optimizedToken.transfer(userB, amount);

        // 对比最终状态
        assertEq(
            legacyToken.balanceOf(userA),
            optimizedToken.balanceOf(userA),
            "Sender balance mismatch"
        );
        assertEq(
            legacyToken.balanceOf(userB),
            optimizedToken.balanceOf(userB),
            "Recipient balance mismatch"
        );
        assertEq(
            legacyToken.getLastTransfer(userA),
            optimizedToken.getLastTransfer(userA),
            "LastTransfer mismatch"
        );
    }

    // 权限控制差分测试
    function testDiff_Mint() public {
        // 测试非owner调用（明确以 userA 身份）
        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", userA));
        legacyToken.mint(userB, 1000);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", userA));
        optimizedToken.mint(userB, 1000);
        vm.stopPrank();

        // 测试owner调用
        vm.prank(owner);
        legacyToken.mint(userB, 1000);

        vm.prank(owner);
        optimizedToken.mint(userB, 1000);

        assertEq(
            legacyToken.balanceOf(userB),
            optimizedToken.balanceOf(userB),
            "Mint result mismatch"
        );
    }
}