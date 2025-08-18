// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyERC20 is ERC20, Ownable {
    // 存储用户最后转账时间（用于演示存储优化）
    mapping(address => uint256) private _lastTransfer;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {
         // 初始化代币：名称、符号、初始供应量
         _mint(msg.sender, 1000000 * 10**decimals());
    }

    // 只有所有者可以调用的铸币函数
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
        _updateLastTransfer(to);
    }

    // 重写转账函数，添加最后转账时间记录
    function transfer(address to, uint256 amount) public override returns (bool) {
        _updateLastTransfer(_msgSender());
        _updateLastTransfer(to);
        return super.transfer(to, amount);
    }

    // 查询最后转账时间
    function getLastTransfer(address account) public view returns (uint256) {
        return _lastTransfer[account];
    }

    // 内部函数：更新最后转账时间
    function _updateLastTransfer(address account) private {
        _lastTransfer[account] = block.timestamp;
    }
}