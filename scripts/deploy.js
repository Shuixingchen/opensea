const { BigNumber } = require("ethers");
const hre = require("hardhat");
const { web3 } = require("hardhat");
const fs = require("fs");

let saveData = {};
async function saveAddress(name,address){
    saveData[name] = address;
    fs.writeFileSync("./build/"+hre.network.config.buildName, JSON.stringify(saveData, null, 4));
}

async function deploy(name, ...arg){
    const factory = await hre.ethers.getContractFactory(name);
    const contract = await factory.deploy(...arg);
    const instance = await contract.deployed();
    saveAddress(name, instance.address);
    return instance;
}

async function main() {
    let networkName = await hre.network.name;
    if (networkName == "dashboardPub"){
        const [singer1] = await hre.ethers.getSigners();

        const mockToken = await deploy("MockToken");
        await(await mockToken.mint(singer1.address, hre.ethers.utils.parseEther("10000000"))).wait();
    
        const mockNFT = await deploy("MockNFT");
        let gasLimit = await mockNFT.estimateGas.safeMint(singer1.address, 5);
        gasLimit =  Math.floor(gasLimit * 1.5);
        await(await mockNFT.safeMint(singer1.address, 5, {gasLimit:gasLimit})).wait();
    
        const proxyRegistry = await deploy("ProxyRegistry");
        const tokenTransferProxy = await deploy("TokenTransferProxy", proxyRegistry.address);
        const exchange = await deploy("Exchange", proxyRegistry.address, tokenTransferProxy.address, mockToken.address, singer1.address);
    
        await(await exchange.changeMinimumMakerProtocolFee(250)).wait();
        await(await exchange.changeMinimumTakerProtocolFee(250)).wait();
        await(await proxyRegistry.grantInitialAuthentication(exchange.address)).wait();

        //await deploy("ExchangeTest");
    }
    else{
        const [singer1,singer2,singer3] = await hre.ethers.getSigners();

        const test = await deploy("Test");
        
        const mockToken = await deploy("MockToken");
        await(await mockToken.mint(singer1.address, hre.web3.utils.toWei("1000000", "ether"))).wait();
        await(await mockToken.mint(singer2.address, hre.web3.utils.toWei("2000000", "ether"))).wait();
    
        const mockNFT = await deploy("MockNFT");
        await(await mockNFT.safeMint(singer1.address, 10)).wait();
        await(await mockNFT.safeMint(singer2.address, 20)).wait();
    
        const proxyRegistry = await deploy("ProxyRegistry");
        const tokenTransferProxy = await deploy("TokenTransferProxy", proxyRegistry.address);
        const exchange = await deploy("Exchange", proxyRegistry.address, tokenTransferProxy.address, mockToken.address, singer3.address);
    
        await(await exchange.changeMinimumMakerProtocolFee(250)).wait();
        await(await exchange.changeMinimumTakerProtocolFee(250)).wait();
        await(await proxyRegistry.grantInitialAuthentication(exchange.address)).wait();
    }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});