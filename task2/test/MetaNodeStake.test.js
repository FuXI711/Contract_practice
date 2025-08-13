const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("MetaNodeStake 完整测试", function () {
  let metaNodeToken, metaNodeStake, owner, user1, user2;
  let metaNodeTokenAddress, stakeAddress;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    
    // 部署 MetaNode 代币
    const MetaNodeToken = await ethers.getContractFactory("MetaNodeToken");
    metaNodeToken = await MetaNodeToken.deploy();
    await metaNodeToken.waitForDeployment();
    metaNodeTokenAddress = await metaNodeToken.getAddress();
    
    // 部署 MetaNodeStake 质押合约
    const MetaNodeStake = await ethers.getContractFactory("MetaNodeStake");
    const currentBlock = await ethers.provider.getBlockNumber();
    const startBlock = currentBlock + 5;
    const endBlock = startBlock + 1000;
    const metaNodePerBlock = ethers.parseUnits("1", 18);
    
    metaNodeStake = await upgrades.deployProxy(
      MetaNodeStake,
      [metaNodeTokenAddress, startBlock, endBlock, metaNodePerBlock],
      { initializer: "initialize", kind: "uups" }
    );
    await metaNodeStake.waitForDeployment();
    stakeAddress = await metaNodeStake.getAddress();
    
    // 转移代币到质押合约
    const deployerBalance = await metaNodeToken.balanceOf(owner.address);
    const transferAmount = deployerBalance * 80n / 100n;
    await metaNodeToken.connect(owner).transfer(stakeAddress, transferAmount);
    
    // 添加ETH池
    await metaNodeStake.connect(owner).addPool(
      ethers.ZeroAddress, 100, ethers.parseEther("0.001"), 10, true
    );
    
    // 添加MetaNode代币池
    await metaNodeStake.connect(owner).addPool(
      metaNodeTokenAddress, 50, ethers.parseUnits("1", 18), 5, true
    );
  });

  describe("合约部署", function () {
    it("应该正确部署 MetaNode 代币", async function () {
      expect(await metaNodeToken.name()).to.equal("MetaNodeToken");
      expect(await metaNodeToken.symbol()).to.equal("MetaNode");
      expect(await metaNodeToken.totalSupply()).to.equal(ethers.parseUnits("10000000", 18));
    });

    it("应该正确部署 MetaNodeStake 质押合约", async function () {
      expect(await metaNodeStake.MetaNode()).to.equal(metaNodeTokenAddress);
      expect(await metaNodeStake.poolLength()).to.equal(2);
    });

    it("应该正确设置质押参数", async function () {
      const currentBlock = await ethers.provider.getBlockNumber();
      expect(await metaNodeStake.startBlock()).to.be.gt(currentBlock);
      expect(await metaNodeStake.endBlock()).to.be.gt(await metaNodeStake.startBlock());
      expect(await metaNodeStake.MetaNodePerBlock()).to.equal(ethers.parseUnits("1", 18));
    });
  });

  describe("资金池管理", function () {
    it("应该正确添加ETH质押池", async function () {
      const pool = await metaNodeStake.pool(0);
      expect(pool.stTokenAddress).to.equal(ethers.ZeroAddress);
      expect(pool.poolWeight).to.equal(100);
      expect(pool.minDepositAmount).to.equal(ethers.parseEther("0.001"));
      expect(pool.unstakeLockedBlocks).to.equal(10);
    });

    it("应该正确添加MetaNode代币质押池", async function () {
      const pool = await metaNodeStake.pool(1);
      expect(pool.stTokenAddress).to.equal(metaNodeTokenAddress);
      expect(pool.poolWeight).to.equal(50);
      expect(pool.minDepositAmount).to.equal(ethers.parseUnits("1", 18));
      expect(pool.unstakeLockedBlocks).to.equal(5);
    });

    it("应该正确计算总池权重", async function () {
      expect(await metaNodeStake.totalPoolWeight()).to.equal(150);
    });
  });

  describe("ETH质押功能", function () {
    it("用户应该能够质押ETH", async function () {
      const depositAmount = ethers.parseEther("0.01");
      await metaNodeStake.connect(user1).depositETH({ value: depositAmount });
      
      const stakingBalance = await metaNodeStake.stakingBalance(0, user1.address);
      expect(stakingBalance).to.equal(depositAmount);
    });

    it("质押金额应该满足最小要求", async function () {
      const smallAmount = ethers.parseEther("0.0001"); // 小于最小质押量
      await expect(
        metaNodeStake.connect(user1).depositETH({ value: smallAmount })
      ).to.be.revertedWith("deposit amount is too small");
    });

    it("质押后池总金额应该增加", async function () {
      const depositAmount = ethers.parseEther("0.01");
      await metaNodeStake.connect(user1).depositETH({ value: depositAmount });
      
      const pool = await metaNodeStake.pool(0);
      expect(pool.stTokenAmount).to.equal(depositAmount);
    });
  });

  describe("MetaNode代币质押功能", function () {
    beforeEach(async function () {
      // 给用户1一些MetaNode代币
      const user1TokenAmount = ethers.parseUnits("100", 18);
      await metaNodeToken.connect(owner).transfer(user1.address, user1TokenAmount);
    });

    it("用户应该能够质押MetaNode代币", async function () {
      const depositAmount = ethers.parseUnits("10", 18);
      
      // 先授权
      await metaNodeToken.connect(user1).approve(stakeAddress, depositAmount);
      
      // 质押
      await metaNodeStake.connect(user1).deposit(1, depositAmount);
      
      const stakingBalance = await metaNodeStake.stakingBalance(1, user1.address);
      expect(stakingBalance).to.equal(depositAmount);
    });

    it("质押前应该先授权", async function () {
      const depositAmount = ethers.parseUnits("10", 18);
      
      await expect(
        metaNodeStake.connect(user1).deposit(1, depositAmount)
      ).to.be.reverted;
    });
  });

  describe("奖励计算", function () {
    beforeEach(async function () {
      // 用户1质押ETH
      await metaNodeStake.connect(user1).depositETH({ value: ethers.parseEther("0.01") });
    });

    it("应该能够计算待领取奖励", async function () {
      // 推进几个区块
      await ethers.provider.send("evm_mine", []);
      await ethers.provider.send("evm_mine", []);
      
      const pendingReward = await metaNodeStake.pendingMetaNode(0, user1.address);
      expect(pendingReward).to.be.gt(0);
    });

    it("奖励应该随时间增加", async function () {
      const reward1 = await metaNodeStake.pendingMetaNode(0, user1.address);
      
      await ethers.provider.send("evm_mine", []);
      
      const reward2 = await metaNodeStake.pendingMetaNode(0, user1.address);
      expect(reward2).to.be.gt(reward1);
    });
  });

  describe("奖励领取", function () {
    beforeEach(async function () {
      // 用户1质押ETH
      await metaNodeStake.connect(user1).depositETH({ value: ethers.parseEther("0.01") });
      
      // 推进区块产生奖励
      await ethers.provider.send("evm_mine", []);
      await ethers.provider.send("evm_mine", []);
    });

    it("用户应该能够领取奖励", async function () {
      const balanceBefore = await metaNodeToken.balanceOf(user1.address);
      
      await metaNodeStake.connect(user1).claim(0);
      
      const balanceAfter = await metaNodeToken.balanceOf(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("领取后待领取奖励应该清零", async function () {
      await metaNodeStake.connect(user1).claim(0);
      
      const pendingReward = await metaNodeStake.pendingMetaNode(0, user1.address);
      expect(pendingReward).to.equal(0);
    });
  });

  describe("解质押功能", function () {
    beforeEach(async function () {
      // 用户1质押ETH
      await metaNodeStake.connect(user1).depositETH({ value: ethers.parseEther("0.01") });
    });

    it("用户应该能够申请解质押", async function () {
      const unstakeAmount = ethers.parseEther("0.005");
      await metaNodeStake.connect(user1).unstake(0, unstakeAmount);
      
      const [requestAmount, pendingWithdraw] = await metaNodeStake.withdrawAmount(0, user1.address);
      expect(requestAmount).to.equal(unstakeAmount);
    });

    it("解质押金额不能超过质押余额", async function () {
      const tooMuchAmount = ethers.parseEther("0.02"); // 超过质押余额
      
      await expect(
        metaNodeStake.connect(user1).unstake(0, tooMuchAmount)
      ).to.be.revertedWith("Not enough staking token balance");
    });

    it("解质押后质押余额应该减少", async function () {
      const originalBalance = await metaNodeStake.stakingBalance(0, user1.address);
      const unstakeAmount = ethers.parseEther("0.005");
      
      await metaNodeStake.connect(user1).unstake(0, unstakeAmount);
      
      const newBalance = await metaNodeStake.stakingBalance(0, user1.address);
      expect(newBalance).to.equal(originalBalance - unstakeAmount);
    });
  });

  describe("提取功能", function () {
    beforeEach(async function () {
      // 用户1质押ETH
      await metaNodeStake.connect(user1).depositETH({ value: ethers.parseEther("0.01") });
      
      // 申请解质押
      await metaNodeStake.connect(user1).unstake(0, ethers.parseEther("0.005"));
    });

    it("锁定期内不能提取", async function () {
      await expect(
        metaNodeStake.connect(user1).withdraw(0)
      ).to.be.reverted;
    });

    it("锁定期后应该能够提取", async function () {
      // 推进区块超过锁定期
      for (let i = 0; i < 15; i++) {
        await ethers.provider.send("evm_mine", []);
      }
      
      const ethBalanceBefore = await ethers.provider.getBalance(user1.address);
      
      await metaNodeStake.connect(user1).withdraw(0);
      
      const ethBalanceAfter = await ethers.provider.getBalance(user1.address);
      expect(ethBalanceAfter).to.be.gt(ethBalanceBefore);
    });
  });

  describe("管理员功能", function () {
    it("管理员应该能够暂停提取功能", async function () {
      await metaNodeStake.connect(owner).pauseWithdraw();
      expect(await metaNodeStake.withdrawPaused()).to.be.true;
    });

    it("管理员应该能够暂停领取功能", async function () {
      await metaNodeStake.connect(owner).pauseClaim();
      expect(await metaNodeStake.claimPaused()).to.be.true;
    });

    it("管理员应该能够恢复功能", async function () {
      await metaNodeStake.connect(owner).pauseWithdraw();
      await metaNodeStake.connect(owner).unpauseWithdraw();
      expect(await metaNodeStake.withdrawPaused()).to.be.false;
    });

    it("管理员应该能够更新池参数", async function () {
      const newMinDeposit = ethers.parseEther("0.002");
      const newUnstakeBlocks = 15;
      
      await metaNodeStake.connect(owner).updatePool(0, newMinDeposit, newUnstakeBlocks);
      
      const pool = await metaNodeStake.pool(0);
      expect(pool.minDepositAmount).to.equal(newMinDeposit);
      expect(pool.unstakeLockedBlocks).to.equal(newUnstakeBlocks);
    });

    it("管理员应该能够设置池权重", async function () {
      const newWeight = 150;
      await metaNodeStake.connect(owner).setPoolWeight(0, newWeight, true);
      
      const pool = await metaNodeStake.pool(0);
      expect(pool.poolWeight).to.equal(newWeight);
    });
  });

  describe("多用户场景", function () {
    beforeEach(async function () {
      // 用户1质押ETH
      await metaNodeStake.connect(user1).depositETH({ value: ethers.parseEther("0.01") });
      
      // 用户2质押更多ETH
      await metaNodeStake.connect(user2).depositETH({ value: ethers.parseEther("0.02") });
    });

    it("多个用户应该能够共享奖励池", async function () {
      // 推进区块
      await ethers.provider.send("evm_mine", []);
      await ethers.provider.send("evm_mine", []);
      
      const user1Reward = await metaNodeStake.pendingMetaNode(0, user1.address);
      const user2Reward = await metaNodeStake.pendingMetaNode(0, user2.address);
      
      expect(user1Reward).to.be.gt(0);
      expect(user2Reward).to.be.gt(0);
    });

    it("质押量大的用户应该获得更多奖励", async function () {
      // 推进区块
      await ethers.provider.send("evm_mine", []);
      await ethers.provider.send("evm_mine", []);
      
      const user1Reward = await metaNodeStake.pendingMetaNode(0, user1.address);
      const user2Reward = await metaNodeStake.pendingMetaNode(0, user2.address);
      
      // 用户2质押量是用户1的2倍，奖励应该更多
      expect(user2Reward).to.be.gt(user1Reward);
    });
  });

  describe("边界情况", function () {
    it("非管理员不能调用管理员功能", async function () {
      await expect(
        metaNodeStake.connect(user1).pauseWithdraw()
      ).to.be.reverted;
    });

    it("无效的池ID应该被拒绝", async function () {
      await expect(
        metaNodeStake.connect(user1).deposit(999, ethers.parseEther("0.01"))
      ).to.be.revertedWith("invalid pid");
    });

    it("质押合约应该有足够的代币余额", async function () {
      const stakeBalance = await metaNodeToken.balanceOf(stakeAddress);
      expect(stakeBalance).to.be.gt(0);
    });
  });
});
