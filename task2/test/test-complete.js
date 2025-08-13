const { ethers, upgrades } = require("hardhat");

async function main() {
  console.log("🧪 开始完整测试 MetaNodeStake 合约...");
  
  // 获取测试账户
  const [deployer, user1, user2] = await ethers.getSigners();
  console.log("📝 测试账户:");
  console.log(`   部署者: ${deployer.address}`);
  console.log(`   用户1: ${user1.address}`);
  console.log(`   用户2: ${user2.address}`);
  
  // ==================== 第一步：部署 MetaNode 代币 ====================
  console.log("\n🪙 部署 MetaNode 代币...");
  const MetaNodeToken = await ethers.getContractFactory('MetaNodeToken');
  const metaNodeToken = await MetaNodeToken.deploy();
  await metaNodeToken.waitForDeployment();
  const metaNodeTokenAddress = await metaNodeToken.getAddress();
  console.log("✅ MetaNode 代币部署成功:", metaNodeTokenAddress);
  
  // 验证代币信息
  const tokenName = await metaNodeToken.name();
  const tokenSymbol = await metaNodeToken.symbol();
  const totalSupply = await metaNodeToken.totalSupply();
  console.log(`📊 代币信息: ${tokenName} (${tokenSymbol}) - 总供应量: ${ethers.formatEther(totalSupply)}`);
  
  // ==================== 第二步：部署 MetaNodeStake 质押合约 ====================
  console.log("\n🏦 部署 MetaNodeStake 质押合约...");
  const MetaNodeStake = await ethers.getContractFactory("MetaNodeStake");
  
  // 设置质押参数
  const currentBlock = await deployer.provider.getBlockNumber();
  const startBlock = currentBlock + 5; // 5个区块后开始
  const endBlock = startBlock + 1000; // 1000个区块后结束
  const metaNodePerBlock = ethers.parseUnits("1", 18); // 每区块1个代币
  
  console.log(`📅 质押参数: 开始区块 ${startBlock}, 结束区块 ${endBlock}, 每区块奖励 ${ethers.formatEther(metaNodePerBlock)} MetaNode`);
  
  //初始化质押合约参数,使用uups升级
  const stake = await upgrades.deployProxy(
    MetaNodeStake,
    [metaNodeTokenAddress, startBlock, endBlock, metaNodePerBlock],
    { 
      initializer: "initialize",
      kind: "uups"
    }
  );
  await stake.waitForDeployment();
  const stakeAddress = await stake.getAddress();
  console.log("✅ MetaNodeStake 质押合约部署成功:", stakeAddress);
  
  // ==================== 第三步：转移代币到质押合约 ====================
  console.log("\n💸 转移代币到质押合约...");
  const deployerTokenBalance = await metaNodeToken.balanceOf(deployer.address);
  const transferAmount = deployerTokenBalance * 90n / 100n; // 转移90%的代币
  
  const transferTx = await metaNodeToken.connect(deployer).transfer(stakeAddress, transferAmount);
  await transferTx.wait();
  
  const stakeTokenBalance = await metaNodeToken.balanceOf(stakeAddress);
  console.log(`✅ 转移完成: ${ethers.formatEther(transferAmount)} MetaNode`);
  console.log(`💰 质押合约代币余额: ${ethers.formatEther(stakeTokenBalance)} MetaNode`);
  
  // ==================== 第四步：添加资金池 ====================
  console.log("\n🏊 添加资金池...");
  
  // 添加ETH质押池
  const ethPoolWeight = 100;
  const minDepositAmount = ethers.parseEther("0.001"); // 最小质押0.001 ETH
  const unstakeLockedBlocks = 10; // 解质押锁定10个区块
  
  const addPoolTx = await stake.connect(deployer).addPool(
    ethers.ZeroAddress, // ETH池地址为0
    ethPoolWeight,
    minDepositAmount,
    unstakeLockedBlocks,
    true
  );
  await addPoolTx.wait();
  console.log("✅ ETH质押池添加成功");
  
  // 添加一个ERC20代币池（使用MetaNode代币作为质押代币）
  const tokenPoolWeight = 50;
  const minTokenDeposit = ethers.parseUnits("1", 18); // 最小质押1个MetaNode
  const tokenUnstakeLockedBlocks = 5;
  
  const addTokenPoolTx = await stake.connect(deployer).addPool(
    metaNodeTokenAddress, // 使用MetaNode代币作为质押代币
    tokenPoolWeight,
    minTokenDeposit,
    tokenUnstakeLockedBlocks,
    true
  );
  await addTokenPoolTx.wait();
  console.log("✅ MetaNode代币质押池添加成功");
  
  // 验证资金池
  const poolLength = await stake.poolLength();
  console.log(`✅ 资金池数量: ${poolLength}`);
  
  // ==================== 第五步：测试质押功能 ====================
  console.log("\n🔒 测试质押功能...");
  
  // 给用户1一些MetaNode代币用于质押
  const user1TokenAmount = ethers.parseUnits("100", 18);
  await metaNodeToken.connect(deployer).transfer(user1.address, user1TokenAmount);
  console.log(`💰 用户1获得 ${ethers.formatEther(user1TokenAmount)} MetaNode`);
  
  // 测试ETH质押
  console.log("\n📥 测试ETH质押...");
  const ethDepositAmount = ethers.parseEther("0.01");
  const ethDepositTx = await stake.connect(user1).depositETH({ value: ethDepositAmount });
  await ethDepositTx.wait();
  console.log(`✅ 用户1质押 ${ethers.formatEther(ethDepositAmount)} ETH`);
  
  // 检查质押余额
  const user1EthStaking = await stake.stakingBalance(0, user1.address);
  console.log(`📊 用户1 ETH质押余额: ${ethers.formatEther(user1EthStaking)} ETH`);
  
  // 测试MetaNode代币质押
  console.log("\n📥 测试MetaNode代币质押...");
  const tokenDepositAmount = ethers.parseUnits("10", 18);
  
  // 先授权
  const approveTx = await metaNodeToken.connect(user1).approve(stakeAddress, tokenDepositAmount);
  await approveTx.wait();
  
  const tokenDepositTx = await stake.connect(user1).deposit(1, tokenDepositAmount);
  await tokenDepositTx.wait(); 
  console.log(`✅ 用户1质押 ${ethers.formatEther(tokenDepositAmount)} MetaNode`);
  
  // 检查质押余额
  const user1TokenStaking = await stake.stakingBalance(1, user1.address);
  console.log(`📊 用户1 MetaNode质押余额: ${ethers.formatEther(user1TokenStaking)} MetaNode`);
  
  // ==================== 第六步：测试奖励计算 ====================
  console.log("\n🎁 测试奖励计算...");
  
  // 推进几个区块
  await ethers.provider.send("evm_mine", []);
  await ethers.provider.send("evm_mine", []);
  await ethers.provider.send("evm_mine", []);
  
  // 检查待领取奖励
  const pendingEthReward = await stake.pendingMetaNode(0, user1.address);
  const pendingTokenReward = await stake.pendingMetaNode(1, user1.address);
  
  console.log(`📈 用户1 ETH池待领取奖励: ${ethers.formatEther(pendingEthReward)} MetaNode`);
  console.log(`📈 用户1 MetaNode池待领取奖励: ${ethers.formatEther(pendingTokenReward)} MetaNode`);
  
  // ==================== 第七步：测试领取奖励 ====================
  console.log("\n💰 测试领取奖励...");
  
  const user1BalanceBefore = await metaNodeToken.balanceOf(user1.address);
  
  // 领取ETH池奖励
  const claimEthTx = await stake.connect(user1).claim(0);
  await claimEthTx.wait();
  console.log("✅ 用户1领取ETH池奖励成功");
  
  // 领取MetaNode池奖励
  const claimTokenTx = await stake.connect(user1).claim(1);
  await claimTokenTx.wait();
  console.log("✅ 用户1领取MetaNode池奖励成功");
  
  const user1BalanceAfter = await metaNodeToken.balanceOf(user1.address);
  const rewardReceived = user1BalanceAfter - user1BalanceBefore;
  console.log(`🎉 用户1总共获得奖励: ${ethers.formatEther(rewardReceived)} MetaNode`);
  
  // ==================== 第八步：测试解质押功能 ====================
  console.log("\n🔓 测试解质押功能...");
  
  // 解质押部分ETH
  const unstakeEthAmount = ethers.parseEther("0.005");
  const unstakeEthTx = await stake.connect(user1).unstake(0, unstakeEthAmount);
  await unstakeEthTx.wait();
  console.log(`✅ 用户1申请解质押 ${ethers.formatEther(unstakeEthAmount)} ETH`);
  
  // 解质押部分MetaNode
  const unstakeTokenAmount = ethers.parseUnits("5", 18);
  const unstakeTokenTx = await stake.connect(user1).unstake(1, unstakeTokenAmount);
  await unstakeTokenTx.wait();
  console.log(`✅ 用户1申请解质押 ${ethers.formatEther(unstakeTokenAmount)} MetaNode`);
  
  // 检查解质押请求
  const [ethRequestAmount, ethPendingWithdraw] = await stake.withdrawAmount(0, user1.address);
  const [tokenRequestAmount, tokenPendingWithdraw] = await stake.withdrawAmount(1, user1.address);
  
  console.log(`📋 ETH解质押请求: ${ethers.formatEther(ethRequestAmount)} ETH, 可提取: ${ethers.formatEther(ethPendingWithdraw)} ETH`);
  console.log(`📋 MetaNode解质押请求: ${ethers.formatEther(tokenRequestAmount)} MetaNode, 可提取: ${ethers.formatEther(tokenPendingWithdraw)} MetaNode`);
  
  // ==================== 第九步：测试提取功能 ====================
  console.log("\n💸 测试提取功能...");
  
  // 推进区块以解锁解质押
  for (let i = 0; i < 15; i++) {
    await ethers.provider.send("evm_mine", []);
  }
  
  const user1EthBalanceBefore = await ethers.provider.getBalance(user1.address);
  const user1TokenBalanceBefore = await metaNodeToken.balanceOf(user1.address);
  
  // 提取ETH
  const withdrawEthTx = await stake.connect(user1).withdraw(0);
  await withdrawEthTx.wait();
  console.log("✅ 用户1提取ETH成功");
  
  // 提取MetaNode
  const withdrawTokenTx = await stake.connect(user1).withdraw(1);
  await withdrawTokenTx.wait();
  console.log("✅ 用户1提取MetaNode成功");
  
  const user1EthBalanceAfter = await ethers.provider.getBalance(user1.address);
  const user1TokenBalanceAfter = await metaNodeToken.balanceOf(user1.address);
  
  const ethWithdrawn = user1EthBalanceAfter - user1EthBalanceBefore;
  const tokenWithdrawn = user1TokenBalanceAfter - user1TokenBalanceBefore;
  
  console.log(`💸 用户1提取的ETH: ${ethers.formatEther(ethWithdrawn)} ETH`);
  console.log(`💸 用户1提取的MetaNode: ${ethers.formatEther(tokenWithdrawn)} MetaNode`);
  
  // ==================== 第十步：测试管理员功能 ====================
  console.log("\n👑 测试管理员功能...");
  
  // 测试暂停功能
  const pauseWithdrawTx = await stake.connect(deployer).pauseWithdraw();
  await pauseWithdrawTx.wait();
  console.log("✅ 暂停提取功能成功");
  
  const pauseClaimTx = await stake.connect(deployer).pauseClaim();
  await pauseClaimTx.wait();
  console.log("✅ 暂停领取功能成功");
  
  // 测试恢复功能
  const unpauseWithdrawTx = await stake.connect(deployer).unpauseWithdraw();
  await unpauseWithdrawTx.wait();
  console.log("✅ 恢复提取功能成功");
  
  const unpauseClaimTx = await stake.connect(deployer).unpauseClaim();
  await unpauseClaimTx.wait();
  console.log("✅ 恢复领取功能成功");
  
  // 测试更新池参数
  const newMinDeposit = ethers.parseEther("0.002");
  const newUnstakeBlocks = 15;
  const updatePoolTx = await stake.connect(deployer).updatePool(0, newMinDeposit, newUnstakeBlocks);
  await updatePoolTx.wait();
  console.log("✅ 更新ETH池参数成功");
  
  // 测试设置池权重
  const newPoolWeight = 150;
  const setWeightTx = await stake.connect(deployer).setPoolWeight(0, newPoolWeight, true);
  await setWeightTx.wait();
  console.log("✅ 设置ETH池权重成功");
  
  // ==================== 第十一步：测试多用户场景 ====================
  console.log("\n👥 测试多用户场景...");
  
  // 给用户2一些代币
  const user2TokenAmount = ethers.parseUnits("50", 18);
  await metaNodeToken.connect(deployer).transfer(user2.address, user2TokenAmount);
  
  // 用户2质押ETH
  const user2EthDeposit = ethers.parseEther("0.02");
  const user2EthTx = await stake.connect(user2).depositETH({ value: user2EthDeposit });
  await user2EthTx.wait();
  console.log(`✅ 用户2质押 ${ethers.formatEther(user2EthDeposit)} ETH`);
  
  // 推进区块
  await ethers.provider.send("evm_mine", []);
  await ethers.provider.send("evm_mine", []);
  
  // 检查两个用户的奖励
  const user1NewReward = await stake.pendingMetaNode(0, user1.address);
  const user2Reward = await stake.pendingMetaNode(0, user2.address);
  
  console.log(`📊 用户1待领取奖励: ${ethers.formatEther(user1NewReward)} MetaNode`);
  console.log(`📊 用户2待领取奖励: ${ethers.formatEther(user2Reward)} MetaNode`);
  
  // ==================== 测试完成 ====================
  console.log("\n🎉 所有测试完成！");
  console.log("=" * 60);
  console.log("📋 测试摘要:");
  console.log(`   MetaNode代币: ${metaNodeTokenAddress}`);
  console.log(`   MetaNodeStake质押合约: ${stakeAddress}`);
  console.log(`   测试用户数量: 2`);
  console.log(`   资金池数量: ${poolLength}`);
  console.log("=" * 60);
  
  // 保存测试信息
  const testInfo = {
    metaNodeToken: metaNodeTokenAddress,
    metaNodeStake: stakeAddress,
    testUsers: [user1.address, user2.address],
    deployer: deployer.address,
    testTime: new Date().toISOString()
  };
  
  require('fs').writeFileSync('test-results.json', JSON.stringify(testInfo, null, 2));
  console.log("\n💾 测试结果已保存到 test-results.json");
}

main()
  .then(() => {
    console.log("\n✅ 完整测试执行成功");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ 测试失败:", error);
    process.exit(1);
  });
