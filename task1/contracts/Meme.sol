/**
 * @title Meme 代币合约
 * @dev 这是一个 SHIB 风格的 Meme 代币智能合约
 * @dev 包含代币税、流动性池管理、交易限制等功能
 * @dev 基于 OpenZeppelin 的 ERC20 标准实现
 * @author 开发者
 * @version 1.0.0
 */

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// 导入 OpenZeppelin 合约库
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";        // ERC20 代币标准
import "@openzeppelin/contracts/access/Ownable.sol";           // 所有权管理
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";    // 重入攻击防护

/**
 * @title Meme 代币合约
 * @dev 继承自 ERC20、Ownable 和 ReentrancyGuard
 * @dev 实现代币税、流动性池管理和交易限制功能
 */
contract Meme is ERC20, Ownable, ReentrancyGuard {
    
    // ==================== 代币税相关变量 ====================
    
    /**
     * @dev 代币税比例，以基点为单位 (1 基点 = 0.01%)
     * @dev 500 = 5% 的税率
     * @dev 10000 = 100% 的税率
     */
    uint256 public taxRate = 500; // 固定代币税5%
    
    /**
     * @dev 代币税直接销毁，不发送到特定地址
     * @dev 税费部分通过 _burn 函数直接销毁   erc20不允许转账给零地址，所以税费部分直接销毁
     */
    
    // ==================== 代币供应量 ====================
    
    /**
     * @dev 代币总供应量
     * @dev 1000000000 * 10^18 = 10亿个代币 (考虑 18 位小数)
     */
    uint256 public constant TOTAL_SUPPLY = 1000000000 * 10**18; // 10亿代币

    // ==================== 交易限制相关变量 ====================
    
    /**
     * @dev 单笔交易最大金额限制
     * @dev 默认为总供应量的 1%，防止大额交易操纵市场
     */
    uint256 public maxTransactionAmount = TOTAL_SUPPLY / 100; // 单笔最大交易量 1%
    
    /**
     * @dev 每日最大交易次数限制
     * @dev 防止用户频繁交易操纵市场
     */
    uint256 public maxDailyTransactions = 10; // 每日最大交易次数
    
    /**
     * @dev 用户每日交易次数映射
     * @dev 记录每个地址在当天的交易次数
     */
    mapping(address => uint256) public dailyTransactionCount; // 用户每日交易次数
    
    /**
     * @dev 用户最后交易日期映射
     * @dev 用于判断是否需要重置每日交易计数
     */
    mapping(address => uint256) public lastTransactionDay; // 用户最后交易日期

    // ==================== 流动性池相关变量 ====================
    
    /**
     * @dev 流动性池合约地址
     * @dev 用于与外部流动性池进行交互
     */
    address public liquidityPool; // 流动性池地址
    
    /**
     * @dev 流动性池锁定状态
     * @dev true = 锁定，false = 解锁
     * @dev 锁定时用户无法移除流动性
     */
    bool public liquidityPoolLocked = false; // 流动性池是否锁定
    
    /**
     * @dev 流动性提供者余额映射
     * @dev 记录每个用户提供的流动性数量
     */
    mapping(address => uint256) public liquidityProviderBalance; // 流动性提供者余额
    
    /**
     * @dev 总流动性数量
     * @dev 所有用户提供的流动性总和
     */
    uint256 public totalLiquidity = 0; // 总流动性

    // ==================== 事件定义 ====================
    
    /**
     * @dev 添加流动性事件
     * @param provider 流动性提供者地址
     * @param amount 添加的流动性数量
     */
    event LiquidityAdded(address indexed provider, uint256 amount);
    
    /**
     * @dev 移除流动性事件
     * @param provider 流动性提供者地址
     * @param amount 移除的流动性数量
     */
    event LiquidityRemoved(address indexed provider, uint256 amount);
    
    /**
     * @dev 最大交易金额更新事件
     * @param newAmount 新的最大交易金额
     */
    event MaxTransactionAmountUpdated(uint256 newAmount);
    
    /**
     * @dev 每日最大交易次数更新事件
     * @param newCount 新的每日最大交易次数
     */
    event MaxDailyTransactionsUpdated(uint256 newCount);

    // ==================== 构造函数 ====================
    
    /**
     * @dev 合约构造函数
     * @dev 初始化代币名称、符号和总供应量
     * @dev 将所有代币铸造给合约部署者
     */
    constructor() ERC20("Meme", "MEME") Ownable(msg.sender) {
        // 将总供应量铸造给合约部署者
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    // ==================== 核心转账功能 ====================
    
    /**
     * @dev 重写 ERC20 的 transfer 函数
     * @dev 添加代币税计算和交易限制检查
     * @param to 接收方地址
     * @param amount 转账金额
     * @return 转账是否成功
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        // 检查单笔交易金额限制
        require(amount <= maxTransactionAmount, "Amount exceeds max transaction limit");
        
        // 检查每日交易次数限制
        require(checkDailyLimit(msg.sender), "Daily transaction limit exceeded");
        
        // 更新发送方的交易计数
        updateTransactionCount(msg.sender);
        
        // 计算代币税
        uint256 taxAmount = (amount * taxRate) / 10000;
        
        // 计算实际转账金额（扣除税费）
        uint256 transferAmount = amount - taxAmount;
        
        // 先销毁税费部分（代币税）
        _burn(msg.sender, taxAmount);
        
        // 再转账剩余金额给接收方
        super.transfer(to, transferAmount);
        
        return true;
    }

    /**
     * @dev 重写 ERC20 的 transferFrom 函数
     * @dev 添加代币税计算和交易限制检查
     * @param from 发送方地址
     * @param to 接收方地址
     * @param amount 转账金额
     * @return 转账是否成功
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // 检查单笔交易金额限制
        require(amount <= maxTransactionAmount, "Amount exceeds max transaction limit");
        
        // 检查每日交易次数限制
        require(checkDailyLimit(from), "Daily transaction limit exceeded");
        
        // 更新发送方的交易计数
        updateTransactionCount(from);
        
        // 计算代币税
        uint256 taxAmount = (amount * taxRate) / 10000;
        
        // 计算实际转账金额（扣除税费）
        uint256 transferAmount = amount - taxAmount;
        
        // 先销毁税费部分（代币税）
        _burn(from, taxAmount);
        
        // 再转账剩余金额给接收方
        super.transferFrom(from, to, transferAmount);
        
        return true;
    }

    // ==================== 流动性池管理功能 ====================
    
    /**
     * @dev 添加流动性到池中
     * @dev 用户可以将代币添加到流动性池中
     * @param amount 要添加的代币数量
     */
    function addLiquidity(uint256 amount) public nonReentrant {
        // 检查添加数量是否大于0
        require(amount > 0, "Amount must be greater than 0");
        
        // 检查用户余额是否足够
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // 将代币从用户转移到合约
        _transfer(msg.sender, address(this), amount);
        
        // 更新用户的流动性提供者余额
        liquidityProviderBalance[msg.sender] += amount;
        
        // 更新总流动性
        totalLiquidity += amount;
        
        // 触发添加流动性事件
        emit LiquidityAdded(msg.sender, amount);
    }

    /**
     * @dev 从池中移除流动性
     * @dev 用户可以从流动性池中移除之前添加的代币
     * @param amount 要移除的代币数量
     */
    function removeLiquidity(uint256 amount) public nonReentrant {
        // 检查移除数量是否大于0
        require(amount > 0, "Amount must be greater than 0");
        
        // 检查用户是否有足够的流动性余额
        require(liquidityProviderBalance[msg.sender] >= amount, "Insufficient liquidity balance");
        
        // 检查流动性池是否被锁定
        require(!liquidityPoolLocked, "Liquidity pool is locked");
        
        // 更新用户的流动性提供者余额
        liquidityProviderBalance[msg.sender] -= amount;
        
        // 更新总流动性
        totalLiquidity -= amount;
        
        // 将代币从合约转移给用户
        _transfer(address(this), msg.sender, amount);
        
        // 触发移除流动性事件
        emit LiquidityRemoved(msg.sender, amount);
    }

    /**
     * @dev 查询用户的流动性余额
     * @param user 要查询的用户地址
     * @return 用户的流动性余额
     */
    function getLiquidityBalance(address user) public view returns (uint256) {
        return liquidityProviderBalance[user];
    }

    // ==================== 交易限制检查功能 ====================
    
    /**
     * @dev 检查用户是否超过每日交易限制
     * @param user 要检查的用户地址
     * @return 是否未超过限制（true = 未超过，false = 已超过）
     */
    function checkDailyLimit(address user) public view returns (bool) {
        // 计算当前日期（以天为单位）
        uint256 currentDay = block.timestamp / 1 days;
        
        // 如果是新的一天，重置计数
        if (lastTransactionDay[user] != currentDay) {
            return true; // 新的一天，可以交易
        }
        
        // 检查当日交易次数是否超过限制
        return dailyTransactionCount[user] < maxDailyTransactions;
    }

    /**
     * @dev 更新用户交易计数（内部函数）
     * @param user 要更新计数的用户地址
     */
    function updateTransactionCount(address user) internal {
        // 计算当前日期（以天为单位）
        uint256 currentDay = block.timestamp / 1 days;
        
        // 如果是新的一天，重置计数
        if (lastTransactionDay[user] != currentDay) {
            dailyTransactionCount[user] = 1; // 新的一天，计数为1
            lastTransactionDay[user] = currentDay; // 更新最后交易日期
        } else {
            // 同一天，增加计数
            dailyTransactionCount[user]++;
        }
    }

    // ==================== 管理员功能 ====================
    
    /**
     * @dev 设置单笔最大交易量
     * @dev 只有合约拥有者可以调用此函数
     * @param newMaxAmount 新的最大交易量
     */
    function setMaxTransactionAmount(uint256 newMaxAmount) public onlyOwner {
        // 检查新金额是否大于0
        require(newMaxAmount > 0, "Max amount must be greater than 0");
        
        // 检查新金额是否不超过总供应量的10%
        //require(newMaxAmount <= TOTAL_SUPPLY / 10, "Max amount cannot exceed 10% of total supply");
        
        // 更新最大交易金额
        maxTransactionAmount = newMaxAmount;
        
        // 触发事件
        emit MaxTransactionAmountUpdated(newMaxAmount);
    }

    /**
     * @dev 设置每日最大交易次数
     * @dev 只有合约拥有者可以调用此函数
     * @param newMaxCount 新的每日最大交易次数
     */
    function setMaxDailyTransactions(uint256 newMaxCount) public onlyOwner {
        // 检查新次数是否大于0
        require(newMaxCount > 0, "Max count must be greater than 0");
        
        // 检查新次数是否不超过100次
        require(newMaxCount <= 100, "Max count cannot exceed 100");
        
        // 更新每日最大交易次数
        maxDailyTransactions = newMaxCount;
        
        // 触发事件
        emit MaxDailyTransactionsUpdated(newMaxCount);
    }

    /**
     * @dev 锁定或解锁流动性池
     * @dev 只有合约拥有者可以调用此函数
     * @param locked 是否锁定（true = 锁定，false = 解锁）
     */
    function setLiquidityPoolLocked(bool locked) public onlyOwner {
        liquidityPoolLocked = locked;
    }

    /**
     * @dev 设置流动性池地址
     * @dev 只有合约拥有者可以调用此函数
     * @param poolAddress 流动性池合约地址
     */
    function setLiquidityPool(address poolAddress) public onlyOwner {
        liquidityPool = poolAddress;
    }
}
