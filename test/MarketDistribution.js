const { expect } = require("chai");
const { ethers } = require("hardhat");
const { createWETH, createUniswap } = require("./helpers");
const { utils, BigNumber, constants } = require("ethers");

describe("MarketDistribution", function() {
    let owner, dev, user1, user2, user3, rootedToken, baseToken, eliteToken, marketGeneration, marketDistribution, uniswap;
    const hardCap = utils.parseEther("100");

    beforeEach(async function() {
        [owner, dev, user1, user2, user3] = await ethers.getSigners();
        
        const rootedTokenFactory = await ethers.getContractFactory("RootedToken");
        rootedToken = await rootedTokenFactory.connect(owner).deploy();
        const baseTokenFactory = await ethers.getContractFactory("ERC20Test");
        baseToken = await baseTokenFactory.connect(owner).deploy();
        const eliteTokenFactory = await ethers.getContractFactory("EliteToken");
        eliteToken = await eliteTokenFactory.connect(owner).deploy(baseToken.address);
        uniswap = await createUniswap(owner, baseToken);

        const marketGenerationFactory = await ethers.getContractFactory("MarketGeneration");
        marketGeneration = await marketGenerationFactory.connect(owner).deploy(rootedToken.address, baseToken.address, hardCap, dev.address);        
   
        const marketDistributionFactory = await ethers.getContractFactory("MarketDistribution");
        marketDistribution = await marketDistributionFactory.connect(owner).deploy(rootedToken.address, uniswap.router.address, eliteToken.address, dev.address);

        const rootedTransferGateFactory = await ethers.getContractFactory("RootedTransferGate");
        const rootedTransferGate = await rootedTransferGateFactory.connect(owner).deploy(rootedToken.address, uniswap.router.address);
        await rootedToken.connect(owner).setTransferGate(rootedTransferGate.address);
        await rootedTransferGate.connect(owner).setUnrestrictedController(marketDistribution.address, true);
        await eliteToken.connect(owner).setSweeper(marketDistribution.address, true);
        
        const eliteFloorCalculatorFactory = await ethers.getContractFactory("EliteFloorCalculator");
        const eliteFloorCalculator = await eliteFloorCalculatorFactory.connect(owner).deploy(rootedToken.address, uniswap.factory.address);
        await eliteToken.connect(owner).setFloorCalculator(eliteFloorCalculator.address);

        await rootedToken.connect(owner).transfer(marketGeneration.address, await rootedToken.totalSupply());
        await marketGeneration.connect(owner).activate(marketDistribution.address);
        
        await baseToken.connect(owner).transfer(user1.address, utils.parseEther("1"));
        await baseToken.connect(owner).transfer(user2.address, utils.parseEther("2"));
        await baseToken.connect(owner).transfer(user3.address, utils.parseEther("3"));

        await baseToken.connect(user1).approve(marketGeneration.address, utils.parseEther("1"));
        await baseToken.connect(user2).approve(marketGeneration.address, utils.parseEther("2"));
        await baseToken.connect(user3).approve(marketGeneration.address, utils.parseEther("3"));
                
        await marketGeneration.connect(user1).contribute(utils.parseEther("1"), 1, constants.AddressZero);
        await marketGeneration.connect(user2).contribute(utils.parseEther("2"), 2, constants.AddressZero);
        await marketGeneration.connect(user3).contribute(utils.parseEther("3"), 3, constants.AddressZero);
    })

    it("initializes as expected", async function() {
        expect(await marketDistribution.totalBaseTokenCollected()).to.equal(0);
        expect(await marketDistribution.devCutPercent()).to.equal(900);
        expect(await marketDistribution.preBuyForShillsPercent()).to.equal(200);
        expect(await marketDistribution.preBuyMarketManipulationPercent()).to.equal(900);
    })

    // it("completeSetup() can't be called by non-owner", async function() {
    //     await expect(marketDistribution.connect(user1).completeSetup()).to.be.revertedWith("Owner only");
    // })

    // describe("setupEliteRooted(), setupBaseRooted(), completeSetup(), complete() called", function() {

    //     beforeEach(async function() {
    //         await marketDistribution.connect(owner).setupEliteRooted();
    //         await marketDistribution.connect(owner).setupBaseRooted();
    //         await marketDistribution.connect(owner).completeSetup();
           
    //         //await marketGeneration.connect(owner).complete();
    //     })

    //     it("initialized as expected", async function() {                    
    //         // expect(await rootKitDistribution.totalEthCollected()).to.equal(utils.parseEther("6"));
    //         // expect(await rootKitDistribution.totalRootKitBought()).not.to.equal(0);
    //         // expect(await rootKitDistribution.totalWbtcRootKit()).not.to.equal(0);
    //         // expect(await rootKitDistribution.totalKethRootKit()).not.to.equal(0);
    //     })

    //     it("distributed as expected", async function() {         
    //         // const target = BigNumber.from(utils.parseEther("1.5"));
    //         // expect(BigNumber.from(await weth.balanceOf(owner.address)).gt(target)).to.equal(true);
    //         // expect(BigNumber.from(await weth.balanceOf(rootKitVault.address)).eq(target)).to.equal(true);
    //         // expect(await ethers.provider.getBalance(rootKitDistribution.address)).to.equal(0);
    //     })
    // })
})