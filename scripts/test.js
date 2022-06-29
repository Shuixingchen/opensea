// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { BigNumber } = require("ethers");
const hre = require("hardhat");
const { web3, ethers } = require("hardhat");
const fs = require("fs");

let saveData = null;
async function GetContract(name) {
  if (saveData == null) {
    saveData = JSON.parse(fs.readFileSync("./build/" + hre.network.config.buildName));
  }

  let factory = await hre.ethers.getContractFactory(name);
  let instance = factory.attach(saveData[name]);
  return instance;
}

async function SaveSellOrder(sell,sellOrder){
  saveData[sell] = sellOrder;
  fs.writeFileSync("./build/"+hre.network.config.buildName, JSON.stringify(saveData,null,4));
}
async function GetSellOrder(sell) {
  if (saveData == null) {
    saveData = JSON.parse(fs.readFileSync("./build/" + hre.network.config.buildName));
  }
  return saveData[sell]
}

async function main() {
  const [singer1] = await hre.ethers.getSigners();
  let address1 = "0xe725D38CC421dF145fEFf6eB9Ec31602f95D8097";
  let address2 = "0xD9478B7cf6C4ACD11e90701Aa6C335B93a2C2368";
  let address3 = "0x221581Fa1F2a7E11ad9E2825D46Ea4D15b22F94e";
  let address4 = "0xdBe64A759Da9ac5c4bD4782585a9D3b9711eDfaD";

  const mockToken = await GetContract("MockToken");
  const mockNFT = await GetContract("MockNFT");
  const proxyRegistry = await GetContract("ProxyRegistry");
  const tokenTransferProxy = await GetContract("TokenTransferProxy");
  const exchange = await GetContract("Exchange");

  // 授权所有的
  async function approveAll(address) {
    let authAddress = await proxyRegistry.proxies(address);// 查询
    if (authAddress == "0x0000000000000000000000000000000000000000"){
      let ret = await (await proxyRegistry.registerProxy()).wait(); // 注册
      authAddress = await proxyRegistry.proxies(address);
    }
    await (await mockNFT.setApprovalForAll(authAddress, true)).wait();// 授权nft给钱包地址
    await (await mockToken.approve(tokenTransferProxy.address, "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")).wait();
  }
  // await approveAll(address1);
  //await approveAll(address4);
  //await approveAll(address2);


  // 查询数据
  async function queryAsset(address) {
    console.log("===========================================");
    console.log(address);
    console.log(await hre.web3.eth.getBalance(address));
    let ret = await mockToken.balanceOf(address);
    console.log("token:" + ret);
    ret = await mockNFT.balanceOf(address);
    console.log("nft:" + ret);
    for (let i = 0; i < ret; ++i) {
      console.log(await mockNFT.tokenOfOwnerByIndex(address, i));
    }
  }
  // await queryAsset(address1);
  //await queryAsset(address2);
  // await queryAsset(address3);
  // await queryAsset(address4);

  // 签名出售交易
  async function signOrder(address) {
    const domain = [
      { name: "name", type: "string" },
      { name: "version", type: "string" },
      { name: "chainId", type: "uint256" },
      { name: "verifyingContract", type: "address" }
    ];

    const domainData = {
      name: "Wyvern Exchange Contract",
      version: "2.3",
      chainId: 80001,//31337,80001
      verifyingContract: exchange.address
    };

    const Order = [
      { name: "exchange", type: "address" },
      { name: "maker", type: "address" },
      { name: "taker", type: "address" },
      { name: "makerRelayerFee", type: "uint256" },
      { name: "takerRelayerFee", type: "uint256" },
      { name: "makerProtocolFee", type: "uint256" },
      { name: "takerProtocolFee", type: "uint256" },
      { name: "feeRecipient", type: "address" },
      { name: "feeMethod", type: "uint8" },
      { name: "side", type: "uint8" },
      { name: "saleKind", type: "uint8" },
      { name: "target", type: "address" },
      { name: "howToCall", type: "uint8" },
      { name: "calldata", type: "bytes" },
      { name: "replacementPattern", type: "bytes" },
      { name: "staticTarget", type: "address" },
      { name: "staticExtradata", type: "bytes" },
      { name: "paymentToken", type: "address" },
      { name: "basePrice", type: "uint256" },
      { name: "extra", type: "uint256" },
      { name: "listingTime", type: "uint256" },
      { name: "expirationTime", type: "uint256" },
      { name: "salt", type: "uint256" },
      { name: "nonce", type: "uint256" }
    ];

    const orderData = {
      exchange:exchange.address,
      maker:address,
      taker:"0x0000000000000000000000000000000000000000",
      makerRelayerFee:250,
      takerRelayerFee:0,
      makerProtocolFee:250,
      takerProtocolFee:250,
      feeRecipient:address3,
      feeMethod:1,
      side:1,
      saleKind:0,
      target:mockNFT.address,
      howToCall:0,
      calldata:mockNFT.interface.encodeFunctionData("safeTransferFrom(address,address,uint256)", [address, "0x0000000000000000000000000000000000000000", 3]),
      replacementPattern:"0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000",
      staticTarget:"0x0000000000000000000000000000000000000000",
      staticExtradata:[],
      paymentToken:"0x0000000000000000000000000000000000000000",
      basePrice:1000,
      extra:0,
      listingTime:Math.floor(new Date().getTime() / 1000) - 100,
      expirationTime:Math.floor(new Date().getTime() / 1000) + 36000,
      salt:web3.utils.randomHex(32),
      nonce:0
    };

    let message = {
      types:{
        EIP712Domain:domain,
        Order:Order
      },
      primaryType:"Order",
      domain:domainData,
      message:orderData
    };

    message = JSON.stringify(message);

    console.log(JSON.stringify(orderData));
    
    let sig = await ethers.provider.send("eth_signTypedData_v4", [address, message]);
    console.log(sig);

    ret = await exchange.validateOrder_([orderData.exchange, orderData.maker, orderData.taker, orderData.feeRecipient, orderData.target, orderData.staticTarget, orderData.paymentToken], [orderData.makerRelayerFee, orderData.takerRelayerFee, orderData.makerProtocolFee, orderData.takerProtocolFee, orderData.basePrice, orderData.extra, orderData.listingTime, orderData.expirationTime, orderData.salt], orderData.feeMethod, orderData.side, orderData.saleKind, orderData.howToCall, orderData.calldata,orderData.replacementPattern, orderData.staticExtradata, sig);
    console.log("验证签名："+ret);
    SaveSellOrder(address, orderData)
  }
  // 购买
  async function matchOrder(address, sell, tokenID, sellOrderData, sellSig) {
    const buyOrderData = {
      exchange:exchange.address,
      maker:address,
      taker:"0x0000000000000000000000000000000000000000",
      makerRelayerFee:250,
      takerRelayerFee:0,
      makerProtocolFee:250,
      takerProtocolFee:250,
      feeRecipient:"0x0000000000000000000000000000000000000000",
      feeMethod:1,
      side:0,
      saleKind:0,
      target:mockNFT.address,
      howToCall:0,
      calldata:mockNFT.interface.encodeFunctionData("safeTransferFrom(address,address,uint256)", [sell, address, tokenID]),
      replacementPattern:[],
      staticTarget:"0x0000000000000000000000000000000000000000",
      staticExtradata:[],
      paymentToken:"0x0000000000000000000000000000000000000000",
      basePrice:1000,
      extra:0,
      listingTime:Math.floor(new Date().getTime() / 1000) - 100,
      expirationTime:Math.floor(new Date().getTime() / 1000) + 36000,
      salt:web3.utils.randomHex(32),
      nonce:0
    };

    let buyAddress = [buyOrderData.exchange, buyOrderData.maker, buyOrderData.taker, buyOrderData.feeRecipient, buyOrderData.target, buyOrderData.staticTarget, buyOrderData.paymentToken];
    let sellAddress = [sellOrderData.exchange, sellOrderData.maker, sellOrderData.taker, sellOrderData.feeRecipient, sellOrderData.target, sellOrderData.staticTarget, sellOrderData.paymentToken];
    let addres = buyAddress.concat(sellAddress);

    let buyUint = [buyOrderData.makerRelayerFee, buyOrderData.takerRelayerFee, buyOrderData.makerProtocolFee, buyOrderData.takerProtocolFee, buyOrderData.basePrice, buyOrderData.extra, buyOrderData.listingTime, buyOrderData.expirationTime, buyOrderData.salt];
    let sellUint = [sellOrderData.makerRelayerFee, sellOrderData.takerRelayerFee, sellOrderData.makerProtocolFee, sellOrderData.takerProtocolFee, sellOrderData.basePrice, sellOrderData.extra, sellOrderData.listingTime, sellOrderData.expirationTime, sellOrderData.salt];
    let uints = buyUint.concat(sellUint);

    let buyUint8 = [buyOrderData.feeMethod, buyOrderData.side, buyOrderData.saleKind, buyOrderData.howToCall];
    let sellUint8 = [sellOrderData.feeMethod, sellOrderData.side, sellOrderData.saleKind, sellOrderData.howToCall];
    let uint8s = buyUint8.concat(sellUint8);

    console.log(addres)
    let ret = await exchange.ordersCanMatch_(addres, uints, uint8s, buyOrderData.calldata, sellOrderData.calldata, buyOrderData.replacementPattern, sellOrderData.replacementPattern, buyOrderData.staticExtradata, sellOrderData.staticExtradata);
    console.log("orderCanMatch:"+ret);

    ret = await exchange.orderCalldataCanMatch(buyOrderData.calldata, buyOrderData.replacementPattern, sellOrderData.calldata, sellOrderData.replacementPattern);
    console.log("callDataMatch:"+ret);

    let cost = await exchange.estimateGas.atomicMatch_(addres, uints, uint8s, buyOrderData.calldata, sellOrderData.calldata, buyOrderData.replacementPattern, sellOrderData.replacementPattern, buyOrderData.staticExtradata, sellOrderData.staticExtradata, [[], sellSig], "0x0000000000000000000000000000000000000000000000000000000000000000" , {value:1025});
    console.log(cost);
    await (await exchange.atomicMatch_(addres, uints, uint8s, buyOrderData.calldata, sellOrderData.calldata, buyOrderData.replacementPattern, sellOrderData.replacementPattern, buyOrderData.staticExtradata, sellOrderData.staticExtradata, [[], sellSig], "0x0000000000000000000000000000000000000000000000000000000000000000", {value:1025, gasLimit:cost*2})).wait();
  }
  // await signOrder(address1);

  // 切换metaMask到address2
  // sellOrder = GetSellOrder(address1)
  // console.log(sellOrder)
  // console.log(JSON.parse('{"exchange":"0x72b300C6932777c8A19EBaF72B768C83b450D261","maker":"0xe725D38CC421dF145fEFf6eB9Ec31602f95D8097","taker":"0x0000000000000000000000000000000000000000","makerRelayerFee":250,"takerRelayerFee":0,"makerProtocolFee":250,"takerProtocolFee":250,"feeRecipient":"0x221581Fa1F2a7E11ad9E2825D46Ea4D15b22F94e","feeMethod":1,"side":1,"saleKind":0,"target":"0xc2461fa1c13C479D41c9Bdca38f91C25A452a946","howToCall":0,"calldata":"0x42842e0e000000000000000000000000e725d38cc421df145feff6eb9ec31602f95d809700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002","replacementPattern":"0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000","staticTarget":"0x0000000000000000000000000000000000000000","staticExtradata":[],"paymentToken":"0x0000000000000000000000000000000000000000","basePrice":1000,"extra":0,"listingTime":1656488285,"expirationTime":1656524385,"salt":"0xcd89e505fa2a4adb05d1218b7750a9f46e2020184cb53b848d36e9164c9abefb","nonce":0}'))
  await matchOrder(address2, address1, 3, JSON.parse('{"exchange":"0x72b300C6932777c8A19EBaF72B768C83b450D261","maker":"0xe725D38CC421dF145fEFf6eB9Ec31602f95D8097","taker":"0x0000000000000000000000000000000000000000","makerRelayerFee":250,"takerRelayerFee":0,"makerProtocolFee":250,"takerProtocolFee":250,"feeRecipient":"0x221581Fa1F2a7E11ad9E2825D46Ea4D15b22F94e","feeMethod":1,"side":1,"saleKind":0,"target":"0xc2461fa1c13C479D41c9Bdca38f91C25A452a946","howToCall":0,"calldata":"0x42842e0e000000000000000000000000e725d38cc421df145feff6eb9ec31602f95d809700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003","replacementPattern":"0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000","staticTarget":"0x0000000000000000000000000000000000000000","staticExtradata":[],"paymentToken":"0x0000000000000000000000000000000000000000","basePrice":1000,"extra":0,"listingTime":1656491817,"expirationTime":1656527917,"salt":"0xc6be78844047a51a898dfca26d83371ac6df45dea38f4e266646208ed0001b8f","nonce":0}'), "0x66f73496720e7638e37c9014aa7539eafdfdce61f440a5cd3532c43d670950d34ec0f3d325acab4029999c0f0ca0e1e21d4f0000c8e5701c847d7c6c42ac13e81b");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
