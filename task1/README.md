# Meme 代币合约操作指南

## 项目概述

这是一个 SHIB 风格的 Meme 代币智能合约，基于以太坊区块链开发。合约包含以下核心功能：

- **代币税机制**：每笔交易自动扣除 5% 税费并发送到零地址销毁
- **流动性池管理**：支持用户添加和移除流动性
- **交易限制**：防止恶意操纵市场的安全机制
- **管理员控制**：灵活的合约参数调整功能

## 技术规格

- **代币名称**：Meme
- **代币符号**：MEME
- **总供应量**：1,000,000,000 MEME (10亿代币)
- **代币税**：5% (固定)
- **单笔最大交易量**：总供应量的 1%
- **每日最大交易次数**：10次

## 环境准备

### 1. 安装依赖

```bash
npm install
```

### 2. 配置环境变量

创建 `.env` 文件并配置以下变量：

```env
# 网络配置
PRIVATE_KEY=your_private_key_here
INFURA_PROJECT_ID=your_infura_project_id
ETHERSCAN_API_KEY=your_etherscan_api_key

# 网络 RPC URL
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_project_id
MAINNET_RPC_URL=https://mainnet.infura.io/v3/your_project_id
```

### 3. 编译合约

```bash
npx hardhat compile
```

## 部署指南

### 1. 本地测试网络部署

```bash
# 启动本地节点
npx hardhat node

# 新开终端，部署到本地网络
npx hardhat deploy --network localhost
```

### 2. 测试网络部署 (Sepolia)

```bash
npx hardhat deploy --network sepolia
```

### 3. 主网部署

```bash
npx hardhat deploy --network mainnet
```

### 4. 验证部署

部署成功后，您将看到以下信息：

```
部署用户地址：0x...
Meme 代币合约地址：0x...
代币名称：Meme
代币符号：MEME
总供应量：1000000000.0
合约拥有者：0x...
```

## 合约交互指南

### 1. 基本代币操作

#### 查看代币信息

```javascript
// 获取代币名称
const name = await memeToken.name();

// 获取代币符号
const symbol = await memeToken.symbol();

// 获取总供应量
const totalSupply = await memeToken.totalSupply();

// 获取用户余额
const balance = await memeToken.balanceOf(userAddress);
```

#### 代币转账

```javascript
// 转账代币（自动扣除 5% 税费）
const amount = ethers.parseEther("1000"); // 1000 MEME
await memeToken.transfer(recipientAddress, amount);

// 使用 transferFrom（需要先授权）
await memeToken.approve(spenderAddress, amount);
await memeToken.connect(spender).transferFrom(fromAddress, toAddress, amount);
```

**注意**：转账时会自动扣除 5% 税费，实际接收方只能收到 95% 的代币。

### 2. 流动性池操作

#### 添加流动性

```javascript
// 添加流动性到池中
const liquidityAmount = ethers.parseEther("10000"); // 10000 MEME
await memeToken.addLiquidity(liquidityAmount);

// 查看用户的流动性余额
const liquidityBalance = await memeToken.getLiquidityBalance(userAddress);

// 查看总流动性
const totalLiquidity = await memeToken.totalLiquidity();
```

#### 移除流动性

```javascript
// 移除流动性
const removeAmount = ethers.parseEther("5000"); // 5000 MEME
await memeToken.removeLiquidity(removeAmount);
```

**注意**：如果流动性池被锁定，无法移除流动性。

### 3. 交易限制

#### 查看限制参数

```javascript
// 获取单笔最大交易量
const maxTransactionAmount = await memeToken.maxTransactionAmount();

// 获取每日最大交易次数
const maxDailyTransactions = await memeToken.maxDailyTransactions();

// 检查用户是否超过每日限制
const canTrade = await memeToken.checkDailyLimit(userAddress);

// 查看用户当日交易次数
const dailyCount = await memeToken.dailyTransactionCount(userAddress);
```

### 4. 管理员功能

#### 设置交易限制

```javascript
// 设置单笔最大交易量
const newMaxAmount = ethers.parseEther("5000000"); // 500万 MEME
await memeToken.setMaxTransactionAmount(newMaxAmount);

// 设置每日最大交易次数
const newMaxCount = 20;
await memeToken.setMaxDailyTransactions(newMaxCount);
```

#### 流动性池管理

```javascript
// 锁定流动性池
await memeToken.setLiquidityPoolLocked(true);

// 解锁流动性池
await memeToken.setLiquidityPoolLocked(false);

// 设置流动性池地址
await memeToken.setLiquidityPool(poolAddress);
```

## 前端集成示例

### 1. 使用 ethers.js

```javascript
import { ethers } from 'ethers';

// 连接钱包
const provider = new ethers.BrowserProvider(window.ethereum);
const signer = await provider.getSigner();

// 合约地址和 ABI
const contractAddress = "0x..."; // 部署后的合约地址
const contractABI = [...]; // 合约 ABI

// 创建合约实例
const memeToken = new ethers.Contract(contractAddress, contractABI, signer);

// 转账示例
async function transferTokens(to, amount) {
    try {
        const tx = await memeToken.transfer(to, ethers.parseEther(amount.toString()));
        await tx.wait();
        console.log("转账成功！");
    } catch (error) {
        console.error("转账失败：", error);
    }
}

// 添加流动性示例
async function addLiquidity(amount) {
    try {
        const tx = await memeToken.addLiquidity(ethers.parseEther(amount.toString()));
        await tx.wait();
        console.log("添加流动性成功！");
    } catch (error) {
        console.error("添加流动性失败：", error);
    }
}
```

### 2. 使用 Web3.js

```javascript
import Web3 from 'web3';

// 连接钱包
const web3 = new Web3(window.ethereum);

// 创建合约实例
const memeToken = new web3.eth.Contract(contractABI, contractAddress);

// 转账示例
async function transferTokens(to, amount) {
    const accounts = await web3.eth.getAccounts();
    const from = accounts[0];
    
    try {
        await memeToken.methods.transfer(to, web3.utils.toWei(amount.toString(), 'ether'))
            .send({ from });
        console.log("转账成功！");
    } catch (error) {
        console.error("转账失败：", error);
    }
}
```

## 安全注意事项

### 1. 私钥安全
- 永远不要在代码中硬编码私钥
- 使用环境变量存储敏感信息
- 定期更换私钥

### 2. 合约安全
- 部署前充分测试所有功能
- 使用多签钱包管理合约拥有者权限
- 定期审查合约代码

### 3. 用户安全
- 提醒用户代币税机制
- 说明交易限制规则
- 提供清晰的操作指导

## 常见问题解答

### Q1: 为什么转账后接收方收到的代币比发送的少？
A: 这是正常的代币税机制。每笔交易会自动扣除 5% 的税费并发送到零地址销毁，实际接收方只能收到 95% 的代币。

### Q2: 为什么无法进行大额转账？
A: 合约设置了单笔最大交易量限制（默认总供应量的 1%），这是为了防止恶意操纵市场。

### Q3: 为什么无法移除流动性？
A: 可能的原因：
- 流动性池被管理员锁定
- 尝试移除的金额超过您的流动性余额
- 网络拥堵导致交易失败

### Q4: 如何查看我的交易历史？
A: 您可以通过区块链浏览器（如 Etherscan）查看您的交易历史，或者监听合约事件。

### Q5: 代币税可以调整吗？
A: 当前版本的合约中代币税是固定的 5%，无法调整。如需调整，需要部署新版本的合约。

## 技术支持

如果您在使用过程中遇到问题，请：

1. 检查网络连接和钱包配置
2. 确认合约地址正确
3. 查看错误信息并参考常见问题
4. 联系技术支持团队

## 许可证

本项目采用 MIT 许可证。详见 LICENSE 文件。

---

**免责声明**：本指南仅供参考，不构成投资建议。加密货币投资存在风险，请谨慎投资。
