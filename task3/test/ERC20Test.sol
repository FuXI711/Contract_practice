// test/MyERC20_UnitTest.sol
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MyERC20.sol";

contract MyERC20Test is Test {
    MyERC20 token;
    address owner = address(0x1);
    address userA = address(0x2);
    address userB = address(0x3);

    function setUp() public {
        vm.startPrank(owner);
        token = new MyERC20("TestToken", "TTK");
        vm.stopPrank();

        // 分配初始代币
        token.mint(userA, 1000 * 10**token.decimals());
    }

    // 测试基础转账功能
    function test_Transfer() public {
        vm.prank(userA);
        token.transfer(userB, 500 * 10**token.decimals());

        assertEq(token.balanceOf(userA), 500 * 10**token.decimals());
        assertEq(token.balanceOf(userB), 500 * 10**token.decimals());
        assertGt(token.getLastTransfer(userA), 0);
    }

    // 测试权限控制
    function test_RestrictedMint() public {
        vm.expectRevert("Ownable: caller is not the owner");
        token.mint(userB, 1000); // 非owner调用应该失败

        vm.prank(owner);
        token.mint(userB, 1000); // owner调用应该成功
    }
}