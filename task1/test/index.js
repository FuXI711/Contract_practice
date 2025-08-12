const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Meme 代币合约测试", function () {
  let memeToken;
  let owner;
  let user1;
  let user2;
  let user3;

  // 测试常量
  const TOTAL_SUPPLY = ethers.parseEther("1000000000"); // 10亿代币
  const TAX_RATE = 500; // 5%
  const MAX_TRANSACTION_AMOUNT = TOTAL_SUPPLY / 100n; // 1%
  const MAX_DAILY_TRANSACTIONS = 10;

  beforeEach(async function () {
    // 获取测试账户
    [owner, user1, user2, user3] = await ethers.getSigners();

    // 部署 Meme 代币合约
    const MemeToken = await ethers.getContractFactory("Meme");
    memeToken = await MemeToken.deploy();
  });

  describe("合约部署测试", function () {
    it("应该正确设置代币基本信息", async function () {
      expect(await memeToken.name()).to.equal("Meme");
      expect(await memeToken.symbol()).to.equal("MEME");
      expect(await memeToken.totalSupply()).to.equal(TOTAL_SUPPLY);
      expect(await memeToken.owner()).to.equal(owner.address);
    });

    it("应该正确设置初始参数", async function () {
      expect(await memeToken.taxRate()).to.equal(TAX_RATE);
      expect(await memeToken.maxTransactionAmount()).to.equal(MAX_TRANSACTION_AMOUNT);
      expect(await memeToken.maxDailyTransactions()).to.equal(MAX_DAILY_TRANSACTIONS);
      expect(await memeToken.liquidityPoolLocked()).to.equal(false);
    });

    it("应该将所有代币分配给部署者", async function () {
      expect(await memeToken.balanceOf(owner.address)).to.equal(TOTAL_SUPPLY);
    });
  });

  describe("代币税功能测试", function () {
    const transferAmount = ethers.parseEther("1000");
    const expectedTax = (transferAmount * BigInt(TAX_RATE)) / 10000n;
    const expectedTransferAmount = transferAmount - expectedTax;

    it("转账时应该正确计算和扣除税费", async function () {
      const initialBalance = await memeToken.balanceOf(owner.address);
      
      await memeToken.transfer(user1.address, transferAmount);
      
      // 检查接收方收到的金额（扣除税费）
      expect(await memeToken.balanceOf(user1.address)).to.equal(expectedTransferAmount);
      
      // 检查发送方扣除的金额（包含税费）
      expect(await memeToken.balanceOf(owner.address)).to.equal(initialBalance - transferAmount);
      
      // 检查代币被销毁（总供应量减少）
      const newTotalSupply = await memeToken.totalSupply();
      expect(newTotalSupply).to.equal(TOTAL_SUPPLY - expectedTax);
    });

    it("transferFrom 时应该正确计算和扣除税费", async function () {
      // 先授权
      await memeToken.approve(user1.address, transferAmount);
      
      const initialBalance = await memeToken.balanceOf(owner.address);
      
      await memeToken.connect(user1).transferFrom(owner.address, user2.address, transferAmount);
      
      // 检查接收方收到的金额（扣除税费）
      expect(await memeToken.balanceOf(user2.address)).to.equal(expectedTransferAmount);
      
      // 检查发送方扣除的金额（包含税费）
      expect(await memeToken.balanceOf(owner.address)).to.equal(initialBalance - transferAmount);
      
      // 检查代币被销毁（总供应量减少）
      const newTotalSupply = await memeToken.totalSupply();
      expect(newTotalSupply).to.equal(TOTAL_SUPPLY - expectedTax);
    });
  });

  describe("交易限制功能测试", function () {
    it("应该拒绝超过单笔最大交易量的转账", async function () {
      const largeAmount = MAX_TRANSACTION_AMOUNT + ethers.parseEther("1");
      
      await expect(
        memeToken.transfer(user1.address, largeAmount)
      ).to.be.revertedWith("Amount exceeds max transaction limit");
    });

    it("应该限制每日交易次数", async function () {
      const smallAmount = ethers.parseEther("100");
      
      // 进行最大允许次数的交易
      for (let i = 0; i < MAX_DAILY_TRANSACTIONS; i++) {
        await memeToken.transfer(user1.address, smallAmount);
      }
      
      // 第11次交易应该失败
      await expect(
        memeToken.transfer(user1.address, smallAmount)
      ).to.be.revertedWith("Daily transaction limit exceeded");
    });

    it("新的一天应该重置交易次数", async function () {
      const smallAmount = ethers.parseEther("100");
      
      // 进行最大允许次数的交易
      for (let i = 0; i < MAX_DAILY_TRANSACTIONS; i++) {
        await memeToken.transfer(user1.address, smallAmount);
      }
      
      // 增加一天时间
      await ethers.provider.send("evm_increaseTime", [86400]); // 24小时
      await ethers.provider.send("evm_mine");
      
      // 现在应该可以再次交易
      await expect(
        memeToken.transfer(user1.address, smallAmount)
      ).to.not.be.reverted;
    });
  });

  describe("流动性池功能测试", function () {
    const liquidityAmount = ethers.parseEther("10000");

    beforeEach(async function () {
      // 给用户1一些代币用于测试
      await memeToken.transfer(user1.address, liquidityAmount * 2n);
    });

    it("应该能够添加流动性", async function () {
      const initialBalance = await memeToken.balanceOf(user1.address);
      
      await memeToken.connect(user1).addLiquidity(liquidityAmount);
      
      // 检查用户余额减少
      expect(await memeToken.balanceOf(user1.address)).to.equal(initialBalance - liquidityAmount);
      
      // 检查流动性提供者余额增加
      expect(await memeToken.getLiquidityBalance(user1.address)).to.equal(liquidityAmount);
      
      // 检查总流动性增加
      expect(await memeToken.totalLiquidity()).to.equal(liquidityAmount);
    });

    it("应该能够移除流动性", async function () {
      // 先添加流动性
      await memeToken.connect(user1).addLiquidity(liquidityAmount);
      
      const removeAmount = ethers.parseEther("5000");
      const initialBalance = await memeToken.balanceOf(user1.address);
      
      await memeToken.connect(user1).removeLiquidity(removeAmount);
      
      // 检查用户余额增加
      expect(await memeToken.balanceOf(user1.address)).to.equal(initialBalance + removeAmount);
      
      // 检查流动性提供者余额减少
      expect(await memeToken.getLiquidityBalance(user1.address)).to.equal(liquidityAmount - removeAmount);
      
      // 检查总流动性减少
      expect(await memeToken.totalLiquidity()).to.equal(liquidityAmount - removeAmount);
    });

    it("锁定流动性池后应该无法移除流动性", async function () {
      // 先添加流动性
      await memeToken.connect(user1).addLiquidity(liquidityAmount);
      
      // 锁定流动性池
      await memeToken.setLiquidityPoolLocked(true);
      
      // 尝试移除流动性应该失败
      await expect(
        memeToken.connect(user1).removeLiquidity(ethers.parseEther("1000"))
      ).to.be.revertedWith("Liquidity pool is locked");
    });

    it("应该拒绝移除超过余额的流动性", async function () {
      await memeToken.connect(user1).addLiquidity(liquidityAmount);
      
      const tooMuchAmount = liquidityAmount + ethers.parseEther("1000");
      
      await expect(
        memeToken.connect(user1).removeLiquidity(tooMuchAmount)
      ).to.be.revertedWith("Insufficient liquidity balance");
    });
  });

  describe("管理员功能测试", function () {
    it("只有拥有者可以设置最大交易量", async function () {
      const newMaxAmount = ethers.parseEther("5000000");
      
      await expect(
        memeToken.connect(user1).setMaxTransactionAmount(newMaxAmount)
      ).to.be.revertedWithCustomError(memeToken, "OwnableUnauthorizedAccount");
      
      await memeToken.setMaxTransactionAmount(newMaxAmount);
      expect(await memeToken.maxTransactionAmount()).to.equal(newMaxAmount);
    });

    it("只有拥有者可以设置每日最大交易次数", async function () {
      const newMaxCount = 20;
      
      await expect(
        memeToken.connect(user1).setMaxDailyTransactions(newMaxCount)
      ).to.be.revertedWithCustomError(memeToken, "OwnableUnauthorizedAccount");
      
      await memeToken.setMaxDailyTransactions(newMaxCount);
      expect(await memeToken.maxDailyTransactions()).to.equal(newMaxCount);
    });

    it("只有拥有者可以锁定流动性池", async function () {
      await expect(
        memeToken.connect(user1).setLiquidityPoolLocked(true)
      ).to.be.revertedWithCustomError(memeToken, "OwnableUnauthorizedAccount");
      
      await memeToken.setLiquidityPoolLocked(true);
      expect(await memeToken.liquidityPoolLocked()).to.equal(true);
    });

    it("应该拒绝设置无效的每日交易次数", async function () {
      await expect(
        memeToken.setMaxDailyTransactions(0)
      ).to.be.revertedWith("Max count must be greater than 0");
      
      await expect(
        memeToken.setMaxDailyTransactions(101)
      ).to.be.revertedWith("Max count cannot exceed 100");
    });
  });

  describe("事件测试", function () {
    it("添加流动性时应该触发 LiquidityAdded 事件", async function () {
      await memeToken.transfer(user1.address, ethers.parseEther("10000"));
      
      await expect(memeToken.connect(user1).addLiquidity(ethers.parseEther("5000")))
        .to.emit(memeToken, "LiquidityAdded")
        .withArgs(user1.address, ethers.parseEther("5000"));
    });

    it("移除流动性时应该触发 LiquidityRemoved 事件", async function () {
      await memeToken.transfer(user1.address, ethers.parseEther("10000"));
      await memeToken.connect(user1).addLiquidity(ethers.parseEther("5000"));
      
      await expect(memeToken.connect(user1).removeLiquidity(ethers.parseEther("2000")))
        .to.emit(memeToken, "LiquidityRemoved")
        .withArgs(user1.address, ethers.parseEther("2000"));
    });

    it("更新最大交易量时应该触发 MaxTransactionAmountUpdated 事件", async function () {
      const newAmount = ethers.parseEther("5000000");
      
      await expect(memeToken.setMaxTransactionAmount(newAmount))
        .to.emit(memeToken, "MaxTransactionAmountUpdated")
        .withArgs(newAmount);
    });

    it("更新每日交易次数时应该触发 MaxDailyTransactionsUpdated 事件", async function () {
      const newCount = 15;
      
      await expect(memeToken.setMaxDailyTransactions(newCount))
        .to.emit(memeToken, "MaxDailyTransactionsUpdated")
        .withArgs(newCount);
    });
  });

  describe("边界条件测试", function () {
    it("应该拒绝添加零数量的流动性", async function () {
      await expect(
        memeToken.addLiquidity(0)
      ).to.be.revertedWith("Amount must be greater than 0");
    });

    it("应该拒绝移除零数量的流动性", async function () {
      await expect(
        memeToken.removeLiquidity(0)
      ).to.be.revertedWith("Amount must be greater than 0");
    });

    it("应该拒绝设置零的最大交易量", async function () {
      await expect(
        memeToken.setMaxTransactionAmount(0)
      ).to.be.revertedWith("Max amount must be greater than 0");
    });

    it("应该正确销毁税费代币", async function () {
      const amount = ethers.parseEther("1000");
      const initialTotalSupply = await memeToken.totalSupply();
      
      // 转账代币（会自动销毁税费部分）
      await memeToken.transfer(user1.address, amount);
      
      // 检查代币被销毁（总供应量减少）
      const taxAmount = (amount * BigInt(TAX_RATE)) / 10000n;
      const newTotalSupply = await memeToken.totalSupply();
      expect(newTotalSupply).to.equal(initialTotalSupply - taxAmount);
    });
  });
});
