// test/MyERC20_FuzzTest.sol
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/MyERC20.sol";

contract MyERC20FuzzTest is Test {
    MyERC20 token;
    address owner = address(0x1);
    address user = address(0x2);

    function setUp() public {
        vm.prank(owner);
        token = new MyERC20("FuzzToken", "FZT");
    }

    // 模糊测试转账边界条件
    function testFuzz_Transfer(
        address to,
        uint128 amount
    ) public {
        // 过滤无效地址和零金额
        vm.assume(to != address(0));
        vm.assume(amount > 0);

        // 初始铸币
        uint256 mintAmount = uint256(amount) * 2;
        vm.prank(owner);
        token.mint(user, mintAmount);

        // 记录预期状态
        uint256 expectedRecipientBalance = token.balanceOf(to) + amount;
        uint256 expectedLastTransfer = block.timestamp;

        // 执行转账
        vm.prank(user);
        token.transfer(to, amount);

        // 验证状态
        assertEq(token.balanceOf(to), expectedRecipientBalance);
        assertEq(token.getLastTransfer(to), expectedLastTransfer);
    }
}