const { ethers } = require("hardhat");

async function main() {
  console.log("🪙 开始部署 MetaNode 代币...");
  
  // 获取部署账户
  const [deployer] = await ethers.getSigners();
  console.log("📝 部署账户:", deployer.address);
  console.log("💰 账户余额:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH");

  // 部署 MetaNode 代币
  console.log("\n🏭 部署 MetaNodeToken 合约...");
  const MetaNodeToken = await ethers.getContractFactory('MetaNodeToken');
  const metaNodeToken = await MetaNodeToken.deploy();
  await metaNodeToken.waitForDeployment();
  
  const metaNodeTokenAddress = await metaNodeToken.getAddress();
  console.log("✅ MetaNode 代币部署成功:", metaNodeTokenAddress);
  
  // 验证代币信息
  const tokenName = await metaNodeToken.name();
  const tokenSymbol = await metaNodeToken.symbol();
  const totalSupply = await metaNodeToken.totalSupply();
  const deployerBalance = await metaNodeToken.balanceOf(deployer.address);
  
  console.log("\n📊 代币信息:");
  console.log(`   名称: ${tokenName}`);
  console.log(`   符号: ${tokenSymbol}`);
  console.log(`   总供应量: ${ethers.formatEther(totalSupply)} ${tokenSymbol}`);
  console.log(`   部署者余额: ${ethers.formatEther(deployerBalance)} ${tokenSymbol}`);
  
  // 保存部署信息
  const deploymentInfo = {
    network: (await ethers.provider.getNetwork()).name,
    deployer: deployer.address,
    metaNodeToken: metaNodeTokenAddress,
    tokenName: tokenName,
    tokenSymbol: tokenSymbol,
    totalSupply: totalSupply.toString(),
    deploymentTime: new Date().toISOString()
  };
  
  require('fs').writeFileSync('token-deployment.json', JSON.stringify(deploymentInfo, null, 2));
  console.log("\n💾 代币部署信息已保存到 token-deployment.json");
  
  console.log("\n🎉 MetaNode 代币部署完成！");
  console.log("=" * 50);
  console.log("📋 下一步:");
  console.log("   1. 复制代币地址:", metaNodeTokenAddress);
  console.log("   2. 运行: npx hardhat run scripts/deploy-stake.js --network sepolia");
  console.log("=" * 50);
}

main()
  .then(() => {
    console.log("\n✅ 代币部署脚本执行成功");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ 代币部署失败:", error);
    process.exit(1);
  });
