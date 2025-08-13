// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 导入OpenZeppelin标准库
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";           // ERC20代币接口
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";  // 安全的ERC20转账工具
import "@openzeppelin/contracts/utils/Address.sol";                // 地址工具库
import "@openzeppelin/contracts/utils/math/Math.sol";              // 数学计算工具库

// 导入OpenZeppelin可升级合约库
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";           // 初始化接口
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";         // UUPS代理升级接口
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";     // 访问控制接口
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";           // 暂停功能接口

/**
 * @title MetaNodeStake
 * @dev MetaNode质押合约，支持多池质押和奖励分配
 * 继承自多个OpenZeppelin可升级合约，提供完整的质押、奖励和升级功能
 */
contract MetaNodeStake is
    Initializable,                    // 提供初始化功能
    UUPSUpgradeable,                  // 提供UUPS代理升级功能
    PausableUpgradeable,              // 提供暂停/恢复功能
    AccessControlUpgradeable          // 提供基于角色的访问控制
{
    // 使用SafeERC20库进行安全的ERC20代币操作
    using SafeERC20 for IERC20;
    // 使用Address库进行地址相关操作
    using Address for address;
    // 使用Math库进行安全的数学计算
    using Math for uint256;

    // ************************************** 常量定义 **************************************

    // 管理员角色标识符，用于访问控制
    bytes32 public constant ADMIN_ROLE = keccak256("admin_role");
    // 升级角色标识符，用于合约升级权限控制
    bytes32 public constant UPGRADE_ROLE = keccak256("upgrade_role");

    // ETH池的池ID，固定为0，表示第一个池是ETH质押池
    uint256 public constant ETH_PID = 0;
    
    // ************************************** 数据结构定义 **************************************
    /*
    奖励计算原理：
    在任何时间点，用户应得但尚未分配的MetaNode数量为：
    pending MetaNode = (user.stAmount * pool.accMetaNodePerST) - user.finishedMetaNode

    当用户向池中存入或提取质押代币时，会发生以下步骤：
    1. 更新池的 `accMetaNodePerST` 和 `lastRewardBlock`
    2. 用户收到待分配的MetaNode奖励
    3. 更新用户的 `stAmount`
    4. 更新用户的 `finishedMetaNode`
    */
    
    /**
     * @dev 质押池结构体，存储池的基本信息和状态
     */
    struct Pool {
        // 质押代币的合约地址，address(0)表示ETH池
        address stTokenAddress;
        // 池的权重，用于计算该池应得的奖励比例
        uint256 poolWeight;
        // 上次分配奖励的区块号，用于计算奖励
        uint256 lastRewardBlock;
        // 每个质押代币累积的MetaNode奖励数量（以1e18为精度）
        uint256 accMetaNodePerST;
        // 池中质押代币的总数量
        uint256 stTokenAmount;
        // 最小质押数量，用户质押必须达到此数量
        uint256 minDepositAmount;
        // 解质押锁定期（区块数），用户申请解质押后需要等待的区块数
        uint256 unstakeLockedBlocks;
    }

    /**
     * @dev 解质押请求结构体，记录用户的解质押申请
     */
    struct UnstakeRequest {
        // 申请解质押的数量
        uint256 amount;
        // 可以释放解质押数量的区块号（解锁时间）
        uint256 unlockBlocks;
    }

    /**
     * @dev 用户信息结构体，存储用户在特定池中的质押和奖励信息
     */
    struct User {
        // 用户提供的质押代币数量
        uint256 stAmount;
        // 用户已完成的MetaNode分配数量（已计算但未领取）
        uint256 finishedMetaNode;
        // 待领取的MetaNode奖励数量
        uint256 pendingMetaNode;
        // 解质押请求列表，存储用户的所有解质押申请
        UnstakeRequest[] requests;
    }

    // ************************************** 状态变量 **************************************
    
    // MetaNodeStake开始生效的区块号
    uint256 public startBlock;
    // MetaNodeStake结束的区块号
    uint256 public endBlock;
    // 每个区块的MetaNode代币奖励数量
    uint256 public MetaNodePerBlock;

    // 是否暂停提现功能
    bool public withdrawPaused;
    // 是否暂停领取奖励功能
    bool public claimPaused;

    // MetaNode代币合约地址
    IERC20 public MetaNode;

    // 所有池的总权重（所有池权重的总和）
    uint256 public totalPoolWeight;
    // 质押池数组，存储所有池的信息
    Pool[] public pool;

    // 用户信息映射：池ID => 用户地址 => 用户信息
    mapping (uint256 => mapping (address => User)) public user;

    // ************************************** 事件定义 **************************************

    // 设置MetaNode代币地址时触发
    event SetMetaNode(IERC20 indexed MetaNode);

    // 暂停提现功能时触发
    event PauseWithdraw();

    // 恢复提现功能时触发
    event UnpauseWithdraw();

    // 暂停领取奖励功能时触发
    event PauseClaim();

    // 恢复领取奖励功能时触发
    event UnpauseClaim();

    // 设置开始区块时触发
    event SetStartBlock(uint256 indexed startBlock);

    // 设置结束区块时触发
    event SetEndBlock(uint256 indexed endBlock);

    // 设置每区块奖励数量时触发
    event SetMetaNodePerBlock(uint256 indexed MetaNodePerBlock);

    // 添加新池时触发
    event AddPool(address indexed stTokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardBlock, uint256 minDepositAmount, uint256 unstakeLockedBlocks);

    // 更新池信息时触发
    event UpdatePoolInfo(uint256 indexed poolId, uint256 indexed minDepositAmount, uint256 indexed unstakeLockedBlocks);

    // 设置池权重时触发
    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 totalPoolWeight);

    // 更新池奖励时触发
    event UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardBlock, uint256 totalMetaNode);

    // 用户质押时触发
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);

    // 用户申请解质押时触发
    event RequestUnstake(address indexed user, uint256 indexed poolId, uint256 amount);

    // 用户提现时触发
    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount, uint256 indexed blockNumber);

    // 用户领取奖励时触发
    event Claim(address indexed user, uint256 indexed poolId, uint256 MetaNodeReward);

    // ************************************** 修饰符 **************************************

    /**
     * @dev 检查池ID是否有效的修饰符
     * @param _pid 要检查的池ID
     */
    modifier checkPid(uint256 _pid) {
        require(_pid < pool.length, "invalid pid");
        _;
    }

    /**
     * @dev 检查领取奖励功能是否未暂停的修饰符
     */
    modifier whenNotClaimPaused() {
        require(!claimPaused, "claim is paused");
        _;
    }

    /**
     * @dev 检查提现功能是否未暂停的修饰符
     */
    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "withdraw is paused");
        _;
    }

    /**
     * @notice 初始化合约，设置MetaNode代币地址和基本参数
     * @dev 这是可升级合约的初始化函数，只能调用一次
     * @param _MetaNode MetaNode代币合约地址
     * @param _startBlock 质押开始区块号
     * @param _endBlock 质押结束区块号
     * @param _MetaNodePerBlock 每个区块的MetaNode奖励数量
     */
    function initialize(
        IERC20 _MetaNode,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _MetaNodePerBlock
    ) public initializer {
        // 验证参数有效性：开始区块必须小于等于结束区块，每区块奖励必须大于0
        require(_startBlock <= _endBlock && _MetaNodePerBlock > 0, "invalid parameters");

        // 初始化访问控制系统
        __AccessControl_init();
        // 初始化UUPS升级系统
        __UUPSUpgradeable_init();
        // 授予部署者默认管理员角色
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // 授予部署者升级角色
        _grantRole(UPGRADE_ROLE, msg.sender);
        // 授予部署者管理员角色
        _grantRole(ADMIN_ROLE, msg.sender);

        // 设置MetaNode代币地址
        setMetaNode(_MetaNode);

        // 设置基本参数
        startBlock = _startBlock;
        endBlock = _endBlock;
        MetaNodePerBlock = _MetaNodePerBlock;
    }

    /**
     * @dev 授权升级函数，只有具有UPGRADE_ROLE角色的用户才能升级合约
     * @param newImplementation 新实现合约的地址
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADE_ROLE)
        override
    {
        // 空实现，仅用于权限控制
    }

    // ************************************** 管理员功能 **************************************

    /**
     * @notice 设置MetaNode代币地址，只能由管理员调用
     * @param _MetaNode MetaNode代币合约地址
     */
    function setMetaNode(IERC20 _MetaNode) public onlyRole(ADMIN_ROLE) {
        // 设置MetaNode代币合约地址
        MetaNode = _MetaNode;

        // 触发设置MetaNode事件
        emit SetMetaNode(MetaNode);
    }

    /**
     * @notice 暂停提现功能，只能由管理员调用
     */
    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        // 检查提现功能是否已经被暂停
        require(!withdrawPaused, "withdraw has been already paused");

        // 设置提现暂停标志
        withdrawPaused = true;

        // 触发暂停提现事件
        emit PauseWithdraw();
    }

    /**
     * @notice 恢复提现功能，只能由管理员调用
     */
    function unpauseWithdraw() public onlyRole(ADMIN_ROLE) {
        // 检查提现功能是否已经被恢复
        require(withdrawPaused, "withdraw has been already unpaused");

        // 清除提现暂停标志
        withdrawPaused = false;

        // 触发恢复提现事件
        emit UnpauseWithdraw();
    }

    /**
     * @notice 暂停领取奖励功能，只能由管理员调用
     */
    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        // 检查领取功能是否已经被暂停
        require(!claimPaused, "claim has been already paused");

        // 设置领取暂停标志
        claimPaused = true;

        // 触发暂停领取事件
        emit PauseClaim();
    }

    /**
     * @notice 恢复领取奖励功能，只能由管理员调用
     */
    function unpauseClaim() public onlyRole(ADMIN_ROLE) {
        // 检查领取功能是否已经被恢复
        require(claimPaused, "claim has been already unpaused");

        // 清除领取暂停标志
        claimPaused = false;

        // 触发恢复领取事件
        emit UnpauseClaim();
    }

    /**
     * @notice 更新质押开始区块，只能由管理员调用
     * @param _startBlock 新的开始区块号
     */
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        // 验证开始区块必须小于等于结束区块
        require(_startBlock <= endBlock, "start block must be smaller than end block");

        // 更新开始区块
        startBlock = _startBlock;

        // 触发设置开始区块事件
        emit SetStartBlock(_startBlock);
    }

    /**
     * @notice 更新质押结束区块，只能由管理员调用
     * @param _endBlock 新的结束区块号
     */
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        // 验证开始区块必须小于等于结束区块
        require(startBlock <= _endBlock, "start block must be smaller than end block");

        // 更新结束区块
        endBlock = _endBlock;

        // 触发设置结束区块事件
        emit SetEndBlock(_endBlock);
    }

    /**
     * @notice 更新每个区块的MetaNode奖励数量，只能由管理员调用
     * @param _MetaNodePerBlock 新的每区块奖励数量
     */
    function setMetaNodePerBlock(uint256 _MetaNodePerBlock) public onlyRole(ADMIN_ROLE) {
        // 验证每区块奖励数量必须大于0
        require(_MetaNodePerBlock > 0, "invalid parameter");

        // 更新每区块奖励数量
        MetaNodePerBlock = _MetaNodePerBlock;

        // 触发设置每区块奖励事件
        emit SetMetaNodePerBlock(_MetaNodePerBlock);
    }

    /**
     * @notice 添加新的质押池，只能由管理员调用
     * @dev 注意：不要添加相同的质押代币超过一次，否则MetaNode奖励计算会出现问题
     * @param _stTokenAddress 质押代币合约地址，address(0)表示ETH池
     * @param _poolWeight 池权重，用于计算该池应得的奖励比例
     * @param _minDepositAmount 最小质押数量
     * @param _unstakeLockedBlocks 解质押锁定期（区块数）
     * @param _withUpdate 是否在添加池之前更新所有池的奖励
     */
    function addPool(address _stTokenAddress, uint256 _poolWeight, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks,  bool _withUpdate) public onlyRole(ADMIN_ROLE) {
        // 第一个池默认为ETH池，所以第一个池必须使用address(0x0)
        if (pool.length > 0) {
            // 非第一个池不能使用address(0x0)
            require(_stTokenAddress != address(0x0), "invalid staking token address");
        } else {
            // 第一个池必须使用address(0x0)
            require(_stTokenAddress == address(0x0), "invalid staking token address");
        }
        // 允许最小质押数量为0（注释掉了验证）
        //require(_minDepositAmount > 0, "invalid min deposit amount");
        // 验证解质押锁定期必须大于0
        require(_unstakeLockedBlocks > 0, "invalid withdraw locked blocks");
        // 验证当前区块号必须小于结束区块
        require(block.number < endBlock, "Already ended");

        // 如果需要，在添加池之前更新所有池的奖励
        if (_withUpdate) {
            massUpdatePools();
        }

        // 计算最后奖励区块：如果当前区块大于开始区块则使用当前区块，否则使用开始区块
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        // 更新总池权重
        totalPoolWeight = totalPoolWeight + _poolWeight;

        // 创建新池并添加到池数组中
        pool.push(Pool({
            stTokenAddress: _stTokenAddress,        // 质押代币地址
            poolWeight: _poolWeight,                // 池权重
            lastRewardBlock: lastRewardBlock,       // 最后奖励区块
            accMetaNodePerST: 0,                    // 累积MetaNode奖励（初始为0）
            stTokenAmount: 0,                       // 质押代币总量（初始为0）
            minDepositAmount: _minDepositAmount,    // 最小质押数量
            unstakeLockedBlocks: _unstakeLockedBlocks // 解质押锁定期
        }));

        // 触发添加池事件
        emit AddPool(_stTokenAddress, _poolWeight, lastRewardBlock, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @notice 更新指定池的信息（最小质押数量和解质押锁定期），只能由管理员调用
     * @param _pid 要更新的池ID
     * @param _minDepositAmount 新的最小质押数量
     * @param _unstakeLockedBlocks 新的解质押锁定期（区块数）
     */
    function updatePool(uint256 _pid, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        // 更新池的最小质押数量
        pool[_pid].minDepositAmount = _minDepositAmount;
        // 更新池的解质押锁定期
        pool[_pid].unstakeLockedBlocks = _unstakeLockedBlocks;

        // 触发更新池信息事件
        emit UpdatePoolInfo(_pid, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @notice 更新指定池的权重，只能由管理员调用
     * @param _pid 要更新的池ID
     * @param _poolWeight 新的池权重
     * @param _withUpdate 是否在更新权重之前更新所有池的奖励
     */
    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        // 验证池权重必须大于0
        require(_poolWeight > 0, "invalid pool weight");
        
        // 如果需要，在更新权重之前更新所有池的奖励
        if (_withUpdate) {
            massUpdatePools();
        }

        // 更新总池权重：减去旧权重，加上新权重
        totalPoolWeight = totalPoolWeight - pool[_pid].poolWeight + _poolWeight;
        // 更新池的权重
        pool[_pid].poolWeight = _poolWeight;

        // 触发设置池权重事件
        emit SetPoolWeight(_pid, _poolWeight, totalPoolWeight);
    }

    // ************************************** 查询功能 **************************************

    /**
     * @notice 获取池的数量
     * @return 池数组的长度
     */
    function poolLength() external view returns(uint256) {
        return pool.length;
    }

    /**
     * @notice 计算给定区块范围内的奖励倍数
     * @dev 计算从_from到_to区块之间的奖励倍数，[_from, _to)表示包含_from但不包含_to
     * @param _from 起始区块号（包含）
     * @param _to 结束区块号（不包含）
     * @return multiplier 奖励倍数
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns(uint256 multiplier) {
        // 验证区块范围的有效性：起始区块必须小于等于结束区块
        require(_from <= _to, "invalid block");
        // 如果起始区块小于开始区块，则使用开始区块
        if (_from < startBlock) {_from = startBlock;}
        // 如果结束区块大于结束区块，则使用结束区块
        if (_to > endBlock) {_to = endBlock;}
        // 再次验证区块范围的有效性
        require(_from <= _to, "end block must be greater than start block");
        
        bool success;
        // 计算区块差值与每区块奖励的乘积，使用安全的数学运算防止溢出
        (success, multiplier) = (_to - _from).tryMul(MetaNodePerBlock);
        require(success, "multiplier overflow");
    }

    /**
     * @notice 获取用户在池中的待领取MetaNode数量
     * @param _pid 池ID
     * @param _user 用户地址
     * @return 待领取的MetaNode数量
     */
    function pendingMetaNode(uint256 _pid, address _user) external checkPid(_pid) view returns(uint256) {
        // 调用内部函数，使用当前区块号计算待领取数量
        return pendingMetaNodeByBlockNumber(_pid, _user, block.number);
    }

    /**
     * @notice 根据指定区块号获取用户在池中的待领取MetaNode数量
     * @param _pid 池ID
     * @param _user 用户地址
     * @param _blockNumber 指定的区块号
     * @return 待领取的MetaNode数量
     */
    function pendingMetaNodeByBlockNumber(uint256 _pid, address _user, uint256 _blockNumber) public checkPid(_pid) view returns(uint256) {
        // 获取池和用户信息
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_user];
        uint256 accMetaNodePerST = pool_.accMetaNodePerST;
        uint256 stSupply = pool_.stTokenAmount;

        // 如果指定区块号大于最后奖励区块且池中有质押代币，则计算新的累积奖励
        if (_blockNumber > pool_.lastRewardBlock && stSupply != 0) {
            // 计算奖励倍数
            uint256 multiplier = getMultiplier(pool_.lastRewardBlock, _blockNumber);
            // 计算该池应得的MetaNode数量
            uint256 MetaNodeForPool = multiplier * pool_.poolWeight / totalPoolWeight;
            // 更新累积的MetaNode奖励
            accMetaNodePerST = accMetaNodePerST + MetaNodeForPool * (1 ether) / stSupply;
        }

        // 返回用户应得的MetaNode数量：用户质押数量 * 累积奖励 - 已完成分配 + 待领取数量
        return user_.stAmount * accMetaNodePerST / (1 ether) - user_.finishedMetaNode + user_.pendingMetaNode;
    }

    /**
     * @notice 获取用户在指定池中的质押数量
     * @param _pid 池ID
     * @param _user 用户地址
     * @return 用户的质押数量
     */
    function stakingBalance(uint256 _pid, address _user) external checkPid(_pid) view returns(uint256) {
        return user[_pid][_user].stAmount;
    }

    /**
     * @notice 获取用户的提现信息，包括锁定的解质押数量和已解锁的解质押数量
     * @param _pid 池ID
     * @param _user 用户地址
     * @return requestAmount 总申请解质押数量
     * @return pendingWithdrawAmount 已解锁可提现的数量
     */
    function withdrawAmount(uint256 _pid, address _user) public checkPid(_pid) view returns(uint256 requestAmount, uint256 pendingWithdrawAmount) {
        // 获取用户信息
        User storage user_ = user[_pid][_user];

        // 遍历用户的所有解质押请求
        for (uint256 i = 0; i < user_.requests.length; i++) {
            // 如果解锁区块号小于等于当前区块号，则已解锁
            if (user_.requests[i].unlockBlocks <= block.number) {
                pendingWithdrawAmount = pendingWithdrawAmount + user_.requests[i].amount;
            }
            // 累计总申请数量
            requestAmount = requestAmount + user_.requests[i].amount;
        }
    }

    // ************************************** 公共功能 **************************************

    /**
     * @notice 更新指定池的奖励变量，使其保持最新状态
     * @param _pid 要更新的池ID
     */
    function updatePool(uint256 _pid) public checkPid(_pid) {
        // 获取池信息
        Pool storage pool_ = pool[_pid];

        // 如果当前区块号小于等于最后奖励区块，则无需更新
        if (block.number <= pool_.lastRewardBlock) {
            return;
        }

        // 计算该池应得的MetaNode数量，使用安全的数学运算
        (bool success1, uint256 totalMetaNode) = getMultiplier(pool_.lastRewardBlock, block.number).tryMul(pool_.poolWeight);
        require(success1, "overflow");

        // 根据总权重计算该池的实际奖励数量
        (success1, totalMetaNode) = totalMetaNode.tryDiv(totalPoolWeight);
        require(success1, "overflow");

        uint256 stSupply = pool_.stTokenAmount;
        if (stSupply > 0) {
            // 将奖励数量转换为高精度计算（乘以1e18）
            (bool success2, uint256 totalMetaNode_) = totalMetaNode.tryMul(1 ether);
            require(success2, "overflow");

            // 计算每个质押代币的累积奖励
            (success2, totalMetaNode_) = totalMetaNode_.tryDiv(stSupply);
            require(success2, "overflow");

            // 更新池的累积MetaNode奖励
            (bool success3, uint256 accMetaNodePerST) = pool_.accMetaNodePerST.tryAdd(totalMetaNode_);
            require(success3, "overflow");
            pool_.accMetaNodePerST = accMetaNodePerST;
        }

        // 更新最后奖励区块为当前区块
        pool_.lastRewardBlock = block.number;

        // 触发更新池事件
        emit UpdatePool(_pid, pool_.lastRewardBlock, totalMetaNode);
    }

    /**
     * @notice 更新所有池的奖励变量，注意gas消耗！
     * @dev 此函数会遍历所有池并调用updatePool，gas消耗较高，请谨慎使用
     */
    function massUpdatePools() public {
        // 获取池的总数量
        uint256 length = pool.length;
        // 遍历所有池并更新奖励
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    /**
     * @notice 质押ETH以获得MetaNode奖励
     * @dev 此函数用于质押ETH到ETH池（池ID为0），需要发送ETH作为msg.value
     */
    function depositETH() public whenNotPaused() payable {
        // 获取ETH池信息
        Pool storage pool_ = pool[ETH_PID];
        // 验证ETH池的质押代币地址必须为address(0x0)
        require(pool_.stTokenAddress == address(0x0), "invalid staking token address");

        // 获取用户发送的ETH数量
        uint256 _amount = msg.value;
        // 验证质押数量必须大于等于最小质押数量
        require(_amount >= pool_.minDepositAmount, "deposit amount is too small");

        // 调用内部质押函数
        _deposit(ETH_PID, _amount);
    }

    /**
     * @notice 质押代币以获得MetaNode奖励
     * @dev 质押前，用户需要授权此合约能够转移他们的质押代币
     * @param _pid 要质押到的池ID
     * @param _amount 要质押的代币数量
     */
    function deposit(uint256 _pid, uint256 _amount) public whenNotPaused() checkPid(_pid) {
        // 验证不能质押到ETH池（ETH池使用depositETH函数）
        require(_pid != 0, "deposit not support ETH staking");
        // 获取池信息
        Pool storage pool_ = pool[_pid];
        // 验证质押数量必须大于最小质押数量
        require(_amount > pool_.minDepositAmount, "deposit amount is too small");

        // 如果质押数量大于0，则从用户转移代币到合约
        if(_amount > 0) {
            IERC20(pool_.stTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        }

        // 调用内部质押函数
        _deposit(_pid, _amount);
    }

    /**
     * @notice 申请解质押代币
     * @dev 此函数会创建解质押请求，代币不会立即返还，需要等待锁定期结束后调用withdraw函数
     * @param _pid 要解质押的池ID
     * @param _amount 要解质押的代币数量
     */
    function unstake(uint256 _pid, uint256 _amount) public whenNotPaused() checkPid(_pid) whenNotWithdrawPaused() {
        // 获取池和用户信息
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        // 验证用户有足够的质押代币余额
        require(user_.stAmount >= _amount, "Not enough staking token balance");

        // 更新池的奖励状态
        updatePool(_pid);

        // 计算用户待分配的MetaNode奖励
        uint256 pendingMetaNode_ = user_.stAmount * pool_.accMetaNodePerST / (1 ether) - user_.finishedMetaNode;

        // 如果有待分配的奖励，则添加到用户的待领取奖励中
        if(pendingMetaNode_ > 0) {
            user_.pendingMetaNode = user_.pendingMetaNode + pendingMetaNode_;
        }

        // 如果解质押数量大于0，则处理解质押逻辑
        if(_amount > 0) {
            // 减少用户的质押数量
            user_.stAmount = user_.stAmount - _amount;
            // 创建解质押请求，设置解锁时间为当前区块号加上锁定期
            user_.requests.push(UnstakeRequest({
                amount: _amount,
                unlockBlocks: block.number + pool_.unstakeLockedBlocks
            }));
        }

        // 减少池中的质押代币总量
        pool_.stTokenAmount = pool_.stTokenAmount - _amount;
        // 更新用户已完成的MetaNode分配数量
        user_.finishedMetaNode = user_.stAmount * pool_.accMetaNodePerST / (1 ether);

        // 触发申请解质押事件
        emit RequestUnstake(msg.sender, _pid, _amount);
    }

    /**
     * @notice 提取已解锁的解质押数量
     * @dev 此函数会检查所有解质押请求，提取已解锁的部分，并清理已处理的请求
     * @param _pid 要提取的池ID
     */
    function withdraw(uint256 _pid) public whenNotPaused() checkPid(_pid) whenNotWithdrawPaused() {
        // 获取池和用户信息
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        uint256 pendingWithdraw_;  // 待提取的数量
        uint256 popNum_;           // 需要移除的请求数量
        
        // 遍历所有解质押请求，找到已解锁的请求
        for (uint256 i = 0; i < user_.requests.length; i++) {
            // 如果解锁区块号大于当前区块号，则还未解锁，跳出循环
            if (user_.requests[i].unlockBlocks > block.number) {
                break;
            }
            // 累计已解锁的数量
            pendingWithdraw_ = pendingWithdraw_ + user_.requests[i].amount;
            popNum_++;
        }

        // 将未解锁的请求向前移动，覆盖已解锁的请求
        for (uint256 i = 0; i < user_.requests.length - popNum_; i++) {
            user_.requests[i] = user_.requests[i + popNum_];
        }

        // 移除已处理的请求（从数组末尾弹出）
        for (uint256 i = 0; i < popNum_; i++) {
            user_.requests.pop();
        }

        // 如果有待提取的数量，则进行转账
        if (pendingWithdraw_ > 0) {
            if (pool_.stTokenAddress == address(0x0)) {
                // 如果是ETH池，使用安全的ETH转账
                _safeETHTransfer(msg.sender, pendingWithdraw_);
            } else {
                // 如果是代币池，使用安全的代币转账
                IERC20(pool_.stTokenAddress).safeTransfer(msg.sender, pendingWithdraw_);
            }
        }

        // 触发提取事件
        emit Withdraw(msg.sender, _pid, pendingWithdraw_, block.number);
    }

    /**
     * @notice 领取MetaNode代币奖励
     * @dev 此函数会计算并转移用户应得的所有MetaNode奖励
     * @param _pid 要领取奖励的池ID
     */
    function claim(uint256 _pid) public whenNotPaused() checkPid(_pid) whenNotClaimPaused() {
        // 获取池和用户信息
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        // 更新池的奖励状态
        updatePool(_pid);

        // 计算用户应得的MetaNode奖励：当前质押的奖励 + 待领取的奖励
        uint256 pendingMetaNode_ = user_.stAmount * pool_.accMetaNodePerST / (1 ether) - user_.finishedMetaNode + user_.pendingMetaNode;

        // 如果有待领取的奖励，则进行转账
        if(pendingMetaNode_ > 0) {
            // 清空用户的待领取奖励
            user_.pendingMetaNode = 0;
            // 安全转移MetaNode代币给用户
            _safeMetaNodeTransfer(msg.sender, pendingMetaNode_);
        }

        // 更新用户已完成的MetaNode分配数量
        user_.finishedMetaNode = user_.stAmount * pool_.accMetaNodePerST / (1 ether);

        // 触发领取奖励事件
        emit Claim(msg.sender, _pid, pendingMetaNode_);
    }

    // ************************************** INTERNAL FUNCTION **************************************

    /**
     * @notice 内部质押函数，处理质押逻辑和奖励计算
     * @dev 此函数是质押操作的核心逻辑，处理奖励分配和状态更新
     * @param _pid 要质押到的池ID
     * @param _amount 要质押的代币数量
     */
    function _deposit(uint256 _pid, uint256 _amount) internal {
        // 获取池和用户信息
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        // 更新池的奖励状态
        updatePool(_pid);

        // 如果用户之前已有质押，则计算并分配累积的奖励
        if (user_.stAmount > 0) {
            // 计算用户应得的累积MetaNode奖励，使用安全的数学运算防止溢出
            (bool success1, uint256 accST) = user_.stAmount.tryMul(pool_.accMetaNodePerST);
            require(success1, "user stAmount mul accMetaNodePerST overflow");
            (success1, accST) = accST.tryDiv(1 ether);
            require(success1, "accST div 1 ether overflow");
            
            // 计算待分配的奖励数量
            (bool success2, uint256 pendingMetaNode_) = accST.trySub(user_.finishedMetaNode);
            require(success2, "accST sub finishedMetaNode overflow");

            // 如果有待分配的奖励，则添加到用户的待领取奖励中
            if(pendingMetaNode_ > 0) {
                (bool success3, uint256 _pendingMetaNode) = user_.pendingMetaNode.tryAdd(pendingMetaNode_);
                require(success3, "user pendingMetaNode overflow");
                user_.pendingMetaNode = _pendingMetaNode;
            }
        }

        // 如果质押数量大于0，则更新用户的质押数量
        if(_amount > 0) {
            (bool success4, uint256 stAmount) = user_.stAmount.tryAdd(_amount);
            require(success4, "user stAmount overflow");
            user_.stAmount = stAmount;
        }

        // 更新池中的质押代币总量
        (bool success5, uint256 stTokenAmount) = pool_.stTokenAmount.tryAdd(_amount);
        require(success5, "pool stTokenAmount overflow");
        pool_.stTokenAmount = stTokenAmount;

        // 更新用户已完成的MetaNode分配数量，使用安全的数学运算
        (bool success6, uint256 finishedMetaNode) = user_.stAmount.tryMul(pool_.accMetaNodePerST);
        require(success6, "user stAmount mul accMetaNodePerST overflow");

        (success6, finishedMetaNode) = finishedMetaNode.tryDiv(1 ether);
        require(success6, "finishedMetaNode div 1 ether overflow");

        user_.finishedMetaNode = finishedMetaNode;

        // 触发质押事件
        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * @notice 安全的MetaNode转账函数，防止舍入误差导致池中没有足够的MetaNode
     * @dev 如果合约余额不足，则转移所有可用余额，避免转账失败
     * @param _to 接收MetaNode的地址
     * @param _amount 要转移的MetaNode数量
     */
    function _safeMetaNodeTransfer(address _to, uint256 _amount) internal {
        // 获取合约中MetaNode代币的余额
        uint256 MetaNodeBal = MetaNode.balanceOf(address(this));

        // 如果请求转移的数量大于合约余额，则转移所有可用余额
        if (_amount > MetaNodeBal) {
            MetaNode.transfer(_to, MetaNodeBal);
        } else {
            // 否则转移请求的数量
            MetaNode.transfer(_to, _amount);
        }
    }

    /**
     * @notice 安全的ETH转账函数
     * @dev 使用call方法进行ETH转账，并检查转账结果，确保转账成功
     * @param _to 接收ETH的地址
     * @param _amount 要转移的ETH数量
     */
    function _safeETHTransfer(address _to, uint256 _amount) internal {
        // 使用call方法进行ETH转账，这是推荐的安全转账方式
        (bool success, bytes memory data) = address(_to).call{
            value: _amount
        }("");

        // 检查转账调用是否成功
        require(success, "ETH transfer call failed");
        // 如果返回了数据，则解码并验证转账操作是否成功
        if (data.length > 0) {
            require(
                abi.decode(data, (bool)),
                "ETH transfer operation did not succeed"
            );
        }
    }
}