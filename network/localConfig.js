const { task } = require("hardhat/config");

require("dotenv").config();

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");
require("hardhat-gas-reporter");
require("solidity-coverage");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

task("balance", "Prints an account's balance")
  .addParam("account", "The account's address")
  .setAction(async (taskArgs, hre)=>{
    const account = web3.utils.toChecksumAddress(taskArgs.account);
    const balance = await web3.eth.getBalance(account);

    console.log(web3.utils.fromWei(balance, "ether"), "ETH");
  });

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks:{
    hardhat:{
      accounts:[
        {privateKey:"cdf0487c1d67ba7972361b1df70788a2d4fb5427279d4bb4c12ac653d48e959d", balance:"10000000000000000000000"},//0x8a446433A789b086c1838e29F3013CbD48F09549
        {privateKey:"530f039687ab33757e752f37861342f28a9e2035431eff91f3a18ce9ed826ef1", balance:"10000000000000000000000"},//0xfB07bD608e0F45631d320977d163726dEf8a44B3
        {privateKey:"5bed6beb8008ed625d46c594c6fd73591890c86aa8824257b1f6066f039f7ff5", balance:"10000000000000000000000"}//0x221581Fa1F2a7E11ad9E2825D46Ea4D15b22F94e
      ],
      allowUnlimitedContractSize:true
    }
  },
  solidity: {
    version:"0.8.9",
    settings: {
      optimizer: {
        enabled: false,
        runs: 200,
      },
    },
  }
};
