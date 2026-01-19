const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("MultiStrategyVault Full Scenario", function () {
  let vault, protocolA, protocolB, usdc;
  let admin, manager, user;

  const DECIMALS = 6;
  const DEPOSIT_AMOUNT = ethers.parseUnits("1000", DECIMALS);

  beforeEach(async () => {
    [admin, manager, user] = await ethers.getSigners();

    // 1. Deploy USDC
    const USDC = await ethers.getContractFactory("USDC");
    usdc = await USDC.deploy(admin.address, ethers.parseUnits("1000000", DECIMALS));

    // 2. Deploy Protocols
    const ProtocolA = await ethers.getContractFactory("ProtocolA");
    const ProtocolB = await ethers.getContractFactory("ProtocolB");
    protocolA = await ProtocolA.deploy(await usdc.getAddress());
    protocolB = await ProtocolB.deploy(await usdc.getAddress());

    // 3. Deploy MultiStrategyVault
    const Vault = await ethers.getContractFactory("MultiStrategyVault");
    vault = await Vault.deploy(
      await usdc.getAddress(),
      manager.address,
      "Multi Strategy Vault",
      "MSV"
    );

    // Setup: Mint USDC to user and approve vault
    await usdc.mint(user.address, DEPOSIT_AMOUNT);
    await usdc.connect(user).approve(await vault.getAddress(), DEPOSIT_AMOUNT);
  });

  it("Should handle 60/40 allocation, 10% gain, and locked withdrawal", async function () {
    const protAAddr = await protocolA.getAddress();
    const protBAddr = await protocolB.getAddress();

    // --- STEP 1: USER DEPOSITS 1000 USDC ---
    await vault.connect(user).deposit(DEPOSIT_AMOUNT, user.address);
    expect(await vault.balanceOf(user.address)).to.equal(DEPOSIT_AMOUNT);

    // --- STEP 2: MANAGER SETS 60/40 ALLOCATION ---
    await vault.connect(manager).setAllocations([
      { protocol: protAAddr, targetBps: 6000 },
      { protocol: protBAddr, targetBps: 4000 }
    ]);

    await vault.connect(manager).rebalance();

    expect(await usdc.balanceOf(protAAddr)).to.equal(ethers.parseUnits("600", DECIMALS));
    expect(await usdc.balanceOf(protBAddr)).to.equal(ethers.parseUnits("400", DECIMALS));

    // --- STEP 3: PROTOCOL A INCREASES IN VALUE BY 10% ---
    const profit = ethers.parseUnits("60", DECIMALS);
    await usdc.mint(protAAddr, profit);

    // --- STEP 4: VERIFY VALUATION (~1060 USDC) ---
    const totalAssets = await vault.totalAssets();
    const expectedValue = ethers.parseUnits("1060", DECIMALS);
    
    // FIX: Convert both to Number to avoid Chai BigInt error
    expect(Number(totalAssets)).to.be.closeTo(Number(expectedValue), 100);

    const userShares = await vault.balanceOf(user.address);
    const assetsWorth = await vault.convertToAssets(userShares);
    expect(Number(assetsWorth)).to.be.closeTo(Number(expectedValue), 100);

    // --- STEP 5: WITHDRAW (HANDLE LOCKUP) ---
    const tx = await vault.connect(user).requestWithdraw(userShares);
    const receipt = await tx.wait();
    
    // Robust event parsing
    const log = receipt.logs.find(x => x.fragment && x.fragment.name === 'WithdrawalRequested');
    const requestId = log.args[0]; // requestId is the first indexed param

    // Advance time by 3 minutes
    await network.provider.send("evm_increaseTime", [180]); 
    await network.provider.send("evm_mine");

    // Claim the withdrawal
    const balBefore = await usdc.balanceOf(user.address);
    await vault.connect(user).claimWithdraw(requestId);
    const balAfter = await usdc.balanceOf(user.address);

    // Final check using Number conversion for closeTo compatibility
    const amountReceived = balAfter - balBefore;
    expect(Number(amountReceived)).to.be.closeTo(Number(expectedValue), 100);
  });
});