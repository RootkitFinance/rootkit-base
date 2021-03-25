const { ethers } = require("hardhat");
const { expect } = require("chai");
const { utils } = require("ethers");

describe("FeeSplitter", function() {
    let rooted, feeSplitter, owner, feeCollector1, feeCollector2;
    const burnRate = 2000; // 20%
    const feeCollector1Rate = 2500; // 25%
    const feeCollector2Rate = 5500; // 55%

    beforeEach(async function() {
        [owner, feeCollector1, feeCollector2] = await ethers.getSigners();

        const feeSplitterFactory = await ethers.getContractFactory("FeeSplitter");
        feeSplitter = await feeSplitterFactory.connect(owner).deploy();

        const rootedFactory = await ethers.getContractFactory("RootedToken");
        rooted = await rootedFactory.connect(owner).deploy();
    })

    it("sets fees as expected", async function() {        
        await feeSplitter.setFees(
            rooted.address, 
            burnRate, 
            [feeCollector1.address, feeCollector2.address], 
            [feeCollector1Rate, feeCollector2Rate]);
        
        expect(await feeSplitter.burnRates(rooted.address)).to.equal(burnRate);
        expect(await feeSplitter.feeCollectors(rooted.address, 0)).to.equal(feeCollector1.address);
        expect(await feeSplitter.feeCollectors(rooted.address, 1)).to.equal(feeCollector2.address);
        expect(await feeSplitter.feeRates(rooted.address, 0)).to.equal(feeCollector1Rate);
        expect(await feeSplitter.feeRates(rooted.address, 1)).to.equal(feeCollector2Rate);
    })

    it("reverts setFees because Fee Collectors and Rates are not the same size", async function() {                
        await expect(feeSplitter.setFees(
            rooted.address, 
            burnRate, 
            [feeCollector1.address, feeCollector2.address], 
            [feeCollector1Rate]))
        .to.be.revertedWith("Fee Collectors and Rates should be the same size and not empty");
    })

    it("reverts setFees because Fee Collectors and Rates are empty", async function() {                
        await expect(feeSplitter.setFees(rooted.address, burnRate, [], []))
        .to.be.revertedWith("Fee Collectors and Rates should be the same size and not empty");
    })

    it("reverts payFees because balance is zero", async function() {                
        await expect(feeSplitter.payFees(rooted.address)).to.be.revertedWith("Nothing to pay");
    })

    it("pays fees and burns when setFees is called if balance > 0", async function() {                 
        await feeSplitter.setFees(
            rooted.address, 
            burnRate, 
            [feeCollector1.address, feeCollector2.address], 
            [feeCollector1Rate, feeCollector2Rate]);
        
        await rooted.connect(owner).transfer(feeSplitter.address, utils.parseEther("100"));

        await feeSplitter.setFees(rooted.address, 0, [owner.address], [10000]);

        expect(await rooted.balanceOf(feeSplitter.address)).to.equal(utils.parseEther("0"));
        expect(await rooted.balanceOf(feeCollector1.address)).to.be.equal(utils.parseEther("25"));
        expect(await rooted.balanceOf(feeCollector2.address)).to.be.equal(utils.parseEther("55"));
    })


    it("pays fees and burns as expected", async function() {                 
        await feeSplitter.setFees(
            rooted.address, 
            burnRate, 
            [feeCollector1.address, feeCollector2.address], 
            [feeCollector1Rate, feeCollector2Rate]);
        
        await rooted.connect(owner).transfer(feeSplitter.address, utils.parseEther("100"));

        await feeSplitter.payFees(rooted.address);

        expect(await rooted.balanceOf(feeSplitter.address)).to.equal(utils.parseEther("0"));
        expect(await rooted.balanceOf(feeCollector1.address)).to.be.equal(utils.parseEther("25"));
        expect(await rooted.balanceOf(feeCollector2.address)).to.be.equal(utils.parseEther("55"));
    })

    it("can recover token if fee collectors are not set", async function() {       
        await rooted.connect(owner).transfer(feeSplitter.address, utils.parseEther("100"));
        await feeSplitter.recoverTokens(rooted.address);

        expect(await rooted.balanceOf(feeSplitter.address)).to.equal(0);
        expect(await rooted.balanceOf(owner.address)).to.equal(await rooted.totalSupply());
    })

    it("cannot recover token if fee collectors are set", async function() {
        await rooted.connect(owner).transfer(feeSplitter.address, utils.parseEther("100"));
        await feeSplitter.setFees(
            rooted.address, 
            burnRate, 
            [feeCollector1.address, feeCollector2.address], 
            [feeCollector1Rate, feeCollector2Rate]);

        await expect(feeSplitter.recoverTokens(rooted.address)).to.be.revertedWith();
        expect(await rooted.balanceOf(feeSplitter.address)).to.equal(utils.parseEther("100"));
    })
})