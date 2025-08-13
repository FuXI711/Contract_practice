const { ethers, upgrades } = require("hardhat");

async function main() {
  console.log("🏦 开始部署 MetaNodeStake 质押合约...");
  
  // 获取部署账户
  const [deployer] = await ethers.getSigners();
  console.log("📝 部署账户:", deployer.address);
  
  // 检查是否有代币部署信息
  let tokenAddress;
  try {
    const tokenDeployment = JSON.parse(require('fs').readFileSync('token-deployment.json', 'utf8'));
    tokenAddress = tokenDeployment.metaNodeToken;
    console.log("📄 从 token-deployment.json 读取代币地址:", tokenAddress);
  } catch (error) {
    console.log("❌ 未找到 token-deployment.json 文件");
    console.log("💡 请先运行: npx hardhat run scripts/deploy-token.js --network sepolia");
    process.exit(1);
  }
  
  // 验证代币合约
  console.log("\n🔍 验证代币合约...");
  const MetaNodeToken = await ethers.getContractFactory('MetaNodeToken');
  const metaNodeToken = MetaNodeToken.attach(tokenAddress);
  
  try {
    const tokenName = await metaNodeToken.name();
    const tokenSymbol = await metaNodeToken.symbol();
    console.log(`✅ 代币验证成功: ${tokenName} (${tokenSymbol})`);
  } catch (error) {
    console.log("❌ 代币合约验证失败，请检查地址是否正确");
    process.exit(1);
  }
  
  // 获取当前区块信息
  const currentBlock = await deployer.provider.getBlockNumber();
  console.log("📦 当前区块:", currentBlock);
  
  // 设置质押参数
  console.log("\n⚙️ 设置质押参数...");
  const startBlock = currentBlock + 10; // 10个区块后开始
  const endBlock = startBlock + (365 * 24 * 60 * 60 / 12); // 一年后结束 (假设12秒出块)
  const metaNodePerBlock = ethers.parseUnits("0.1", 18); // 每区块0.1个代币
  
  console.log(`📅 开始区块: ${startBlock}`);
  console.log(`📅 结束区块: ${endBlock}`);
  console.log(`🎁 每区块奖励: ${ethers.formatEther(metaNodePerBlock)} MetaNode`);
  
  // 部署 MetaNodeStake 质押合约
  console.log("\n🏭 部署 MetaNodeStake 合约...");
  const MetaNodeStake = await ethers.getContractFactory("MetaNodeStake");
  
  const stake = await upgrades.deployProxy(
    MetaNodeStake,
    [tokenAddress, startBlock, endBlock, metaNodePerBlock],
    { 
      initializer: "initialize",
      kind: "uups"
    }
  );

  await stake.waitForDeployment();
  const stakeAddress = await stake.getAddress();
  console.log("✅ MetaNodeStake 质押合约部署成功:", stakeAddress);
  
  // 验证合约设置
  console.log("\n🔍 验证合约设置...");
  const contractStartBlock = await stake.startBlock();
  const contractEndBlock = await stake.endBlock();
  const contractMetaNodePerBlock = await stake.MetaNodePerBlock();
  const contractMetaNode = await stake.MetaNode();
  
  console.log("✅ 合约参数验证:");
  console.log(`   - 开始区块: ${contractStartBlock}`);
  console.log(`   - 结束区块: ${contractEndBlock}`);
  console.log(`   - 每区块奖励: ${ethers.formatEther(contractMetaNodePerBlock)}`);
  console.log(`   - MetaNode代币地址: ${contractMetaNode}`);
  
  // 转移代币到质押合约
  console.log("\n💸 转移代币到质押合约...");
  const deployerTokenBalance = await metaNodeToken.balanceOf(deployer.address);
  const transferAmount = deployerTokenBalance * 80n / 100n; // 转移80%的代币
  
  const transferTx = await metaNodeToken.connect(deployer).transfer(stakeAddress, transferAmount);
  await transferTx.wait();
  
  const stakeTokenBalance = await metaNodeToken.balanceOf(stakeAddress);
  console.log(`✅ 转移完成: ${ethers.formatEther(transferAmount)} MetaNode`);
  console.log(`💰 质押合约代币余额: ${ethers.formatEther(stakeTokenBalance)} MetaNode`);
  
  // 添加初始资金池
  console.log("\n🏊 添加初始资金池...");
  const ethPoolWeight = 100;
  const minDepositAmount = ethers.parseEther("0.01"); // 最小质押0.01 ETH
  const unstakeLockedBlocks = 100; // 解质押锁定100个区块
  
  const addPoolTx = await stake.connect(deployer).addPool(
    ethers.ZeroAddress, // ETH池地址为0
    ethPoolWeight,
    minDepositAmount,
    unstakeLockedBlocks,
    true // 更新所有池
  );
  await addPoolTx.wait();
  
  console.log("✅ ETH质押池添加成功");
  console.log(`   - 池权重: ${ethPoolWeight}`);
  console.log(`   - 最小质押量: ${ethers.formatEther(minDepositAmount)} ETH`);
  console.log(`   - 解质押锁定区块: ${unstakeLockedBlocks}`);
  
  // 最终验证
  console.log("\n🎯 最终验证...");
  const poolLength = await stake.poolLength();
  console.log(`✅ 资金池数量: ${poolLength}`);
  
  const adminRole = await stake.ADMIN_ROLE();
  const hasAdminRole = await stake.hasRole(adminRole, deployer.address);
  console.log(`✅ 管理员权限: ${hasAdminRole ? '已设置' : '未设置'}`);
  
  // 保存部署信息
  const deploymentInfo = {
    network: (await ethers.provider.getNetwork()).name,
    deployer: deployer.address,
    metaNodeToken: tokenAddress,
    metaNodeStake: stakeAddress,
    startBlock: startBlock,
    endBlock: endBlock,
    metaNodePerBlock: metaNodePerBlock.toString(),
    deploymentTime: new Date().toISOString()
  };
  
  require('fs').writeFileSync('stake-deployment.json', JSON.stringify(deploymentInfo, null, 2));
  console.log("\n💾 质押合约部署信息已保存到 stake-deployment.json");
  
  // 部署完成
  console.log("\n🎉 部署完成！");
  console.log("=" * 60);
  console.log("📋 部署摘要:");
  console.log(`   MetaNode代币: ${tokenAddress}`);
  console.log(`   MetaNodeStake质押合约: ${stakeAddress}`);
  console.log(`   部署账户: ${deployer.address}`);
  console.log("=" * 60);
  console.log("\n🚀 现在可以开始质押了！");
}

main()
  .then(() => {
    console.log("\n✅ 质押合约部署脚本执行成功");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ 质押合约部署失败:", error);
    process.exit(1);
  });
