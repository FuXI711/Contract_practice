const { ethers, upgrades } = require("hardhat");

async function main() {
  console.log("⚡ 快速测试 MetaNodeStake 核心功能...");
  
  // 获取测试账户
  const [deployer, user] = await ethers.getSigners();
  console.log("📝 测试账户:");
  console.log(`   部署者: ${deployer.address}`);
  console.log(`   用户: ${user.address}`);
  
  // ==================== 部署合约 ====================
  console.log("\n🚀 部署合约...");
  
  // 部署代币
  const MetaNodeToken = await ethers.getContractFactory('MetaNodeToken');
  const metaNodeToken = await MetaNodeToken.deploy();
  await metaNodeToken.waitForDeployment();
  const metaNodeTokenAddress = await metaNodeToken.getAddress();
  console.log("✅ MetaNode 代币部署成功:", metaNodeTokenAddress);
  
  // 部署质押合约
  const MetaNodeStake = await ethers.getContractFactory("MetaNodeStake");
  const currentBlock = await deployer.provider.getBlockNumber();
  const startBlock = currentBlock + 2;
  const endBlock = startBlock + 100;
  const metaNodePerBlock = ethers.parseUnits("1", 18);
  
  const stake = await upgrades.deployProxy(
    MetaNodeStake,
    [metaNodeTokenAddress, startBlock, endBlock, metaNodePerBlock],
    { initializer: "initialize", kind: "uups" }
  );
  await stake.waitForDeployment();
  const stakeAddress = await stake.getAddress();
  console.log("✅ MetaNodeStake 质押合约部署成功:", stakeAddress);
  
  // 转移代币到质押合约
  const deployerBalance = await metaNodeToken.balanceOf(deployer.address);
  const transferAmount = deployerBalance * 80n / 100n;
  await metaNodeToken.connect(deployer).transfer(stakeAddress, transferAmount);
  console.log("✅ 转移代币到质押合约完成");
  
  // 添加ETH池
  await stake.connect(deployer).addPool(
    ethers.ZeroAddress, 100, ethers.parseEther("0.001"), 5, true
  );
  console.log("✅ ETH质押池添加成功");
  
  // ==================== 测试核心功能 ====================
  console.log("\n🧪 测试核心功能...");
  
  // 1. 测试ETH质押
  console.log("1️⃣ 测试ETH质押...");
  const ethAmount = ethers.parseEther("0.01");
  await stake.connect(user).depositETH({ value: ethAmount });
  const stakingBalance = await stake.stakingBalance(0, user.address);
  console.log(`   ✅ 质押成功，余额: ${ethers.formatEther(stakingBalance)} ETH`);
  
  // 2. 测试奖励计算
  console.log("2️⃣ 测试奖励计算...");
  await ethers.provider.send("evm_mine", []);
  await ethers.provider.send("evm_mine", []);
  const pendingReward = await stake.pendingMetaNode(0, user.address);
  console.log(`   ✅ 待领取奖励: ${ethers.formatEther(pendingReward)} MetaNode`);
  
  // 3. 测试领取奖励
  console.log("3️⃣ 测试领取奖励...");
  const balanceBefore = await metaNodeToken.balanceOf(user.address);
  await stake.connect(user).claim(0);
  const balanceAfter = await metaNodeToken.balanceOf(user.address);
  const rewardReceived = balanceAfter - balanceBefore;
  console.log(`   ✅ 领取成功，获得: ${ethers.formatEther(rewardReceived)} MetaNode`);
  
  // 4. 测试解质押
  console.log("4️⃣ 测试解质押...");
  const unstakeAmount = ethers.parseEther("0.005");
  await stake.connect(user).unstake(0, unstakeAmount);
  console.log(`   ✅ 解质押申请成功: ${ethers.formatEther(unstakeAmount)} ETH`);
  
  // 5. 测试提取
  console.log("5️⃣ 测试提取...");
  for (let i = 0; i < 6; i++) {
    await ethers.provider.send("evm_mine", []);
  }
  const ethBalanceBefore = await ethers.provider.getBalance(user.address);
  await stake.connect(user).withdraw(0);
  const ethBalanceAfter = await ethers.provider.getBalance(user.address);
  const ethWithdrawn = ethBalanceAfter - ethBalanceBefore;
  console.log(`   ✅ 提取成功: ${ethers.formatEther(ethWithdrawn)} ETH`);
  
  // ==================== 测试管理员功能 ====================
  console.log("\n👑 测试管理员功能...");
  
  // 测试暂停/恢复
  await stake.connect(deployer).pauseWithdraw();
  console.log("   ✅ 暂停提取功能");
  await stake.connect(deployer).unpauseWithdraw();
  console.log("   ✅ 恢复提取功能");
  
  // 测试更新池参数
  await stake.connect(deployer).updatePool(0, ethers.parseEther("0.002"), 10);
  console.log("   ✅ 更新池参数");
  
  // ==================== 测试完成 ====================
  console.log("\n🎉 快速测试完成！");
  console.log("=" * 50);
  console.log("📋 测试结果:");
  console.log(`   ✅ 合约部署: 成功`);
  console.log(`   ✅ ETH质押: 成功`);
  console.log(`   ✅ 奖励计算: 成功`);
  console.log(`   ✅ 奖励领取: 成功`);
  console.log(`   ✅ 解质押: 成功`);
  console.log(`   ✅ 提取: 成功`);
  console.log(`   ✅ 管理员功能: 成功`);
  console.log("=" * 50);
  
  // 保存测试信息
  const testInfo = {
    metaNodeToken: metaNodeTokenAddress,
    metaNodeStake: stakeAddress,
    testUser: user.address,
    deployer: deployer.address,
    testTime: new Date().toISOString()
  };
  
  require('fs').writeFileSync('quick-test-results.json', JSON.stringify(testInfo, null, 2));
  console.log("\n💾 快速测试结果已保存到 quick-test-results.json");
}

main()
  .then(() => {
    console.log("\n✅ 快速测试执行成功");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ 快速测试失败:", error);
    process.exit(1);
  });
