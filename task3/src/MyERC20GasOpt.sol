// src/MyERC20GasOpt.sol
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyERC20GasOpt is ERC20, Ownable {
    // 存储优化：将时间戳和余额合并到一个存储槽
    struct UserInfo {
        uint96 balance;    // 足够存储 7.9e28 个代币
        uint160 lastTransfer;
    }
    mapping(address => UserInfo) private _userInfo;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {
        uint256 initialSupply = 1000000 * 10**decimals();
        _mint(msg.sender, initialSupply);
        
        // 打包存储写入
        _userInfo[msg.sender] = UserInfo({
            balance: uint96(initialSupply),
            lastTransfer: uint160(block.timestamp)
        });
    }

    // 使用自定义错误节省 Gas
    error InsufficientBalance();
    error BalanceOverflow();

    function mint(address to, uint256 amount) public onlyOwner {
        // 注意：父合约 ERC20 的 _totalSupply 是 private，不能直接修改。
        // 为保持与 OZ 的总供应量与事件语义一致，这里调用父合约 _mint。
        // 这样会更新 OZ 的 _totalSupply 和 _balances，并发出 Transfer(address(0), to, amount) 事件。
        _mint(to, amount);
        
        // 读出现有用户信息（一次 sload 获取 256 位打包字，由编译器完成）。
        // 后续我们在 Yul 中一次性写回，减少到 1 次 sstore。
        UserInfo memory info = _userInfo[to];
        uint256 newBalance = info.balance + amount;
        
        // balance 存在低 96 位，必须确保不溢出。
        if (newBalance > type(uint96).max) revert BalanceOverflow();
        
        // 使用内联汇编一次性写入打包的存储槽，合并 balance 与 lastTransfer：
        // packedData = (uint256(timestamp) << 96) | newBalance
        assembly {
            // 1) 计算 mapping 元素的存储槽：keccak256(abi.encode(to, _userInfo.slot))
            mstore(0x00, to)
            mstore(0x20, _userInfo.slot)
            let slot := keccak256(0x00, 0x40)
            
            // 2) 取当前区块时间戳（Yul 原语），左移 96 位放到高位；低位放 newBalance
            let packedData := or(newBalance, shl(96, timestamp()))
            
            // 3) 一次 sstore 写回，替代原来对 balance 与 lastTransfer 的两次写入
            sstore(slot, packedData)
        }
        // 这里无需再次 emit Transfer 事件，_mint 已经发出。
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        address from = msg.sender;
        UserInfo memory senderInfo = _userInfo[from];
        UserInfo memory recipientInfo = _userInfo[to];

        // 检查余额
        if (senderInfo.balance < amount) revert InsufficientBalance();
        
        // 计算新余额
        uint256 newSenderBalance = senderInfo.balance - amount;
        uint256 newRecipientBalance = recipientInfo.balance + amount;
        
        // 检查接收方余额溢出
        if (newRecipientBalance > type(uint96).max) revert BalanceOverflow();
        
        // 使用内联汇编一次性更新两个地址的存储槽
        assembly {
            let currentTimestamp := timestamp()
            
            // 更新发送方
            mstore(0x00, from)
            mstore(0x20, _userInfo.slot)
            let senderSlot := keccak256(0x00, 0x40)
            let senderPackedData := or(newSenderBalance, shl(96, currentTimestamp))
            sstore(senderSlot, senderPackedData)
            
            // 更新接收方
            mstore(0x00, to)
            mstore(0x20, _userInfo.slot)
            let recipientSlot := keccak256(0x00, 0x40)
            let recipientPackedData := or(newRecipientBalance, shl(96, currentTimestamp))
            sstore(recipientSlot, recipientPackedData)
        }

        emit Transfer(from, to, amount);
        return true;
    }

    // 视图函数使用内联汇编优化
    function balanceOf(address account) public view override returns (uint256 result) {
        assembly {
            // 计算存储槽位置
            mstore(0x00, account)
            mstore(0x20, _userInfo.slot)
            let slot := keccak256(0x00, 0x40)
            
            // 读取打包数据并提取 balance (低 96 位)
            let packedData := sload(slot)
            result := and(packedData, 0xffffffffffffffffffffffff)
        }
    }

    function getLastTransfer(address account) public view returns (uint256 result) {
        assembly {
            // 计算存储槽位置
            mstore(0x00, account)
            mstore(0x20, _userInfo.slot)
            let slot := keccak256(0x00, 0x40)
            
            // 读取打包数据并提取 lastTransfer (高 160 位)
            let packedData := sload(slot)
            result := shr(96, packedData)
        }
    }
}