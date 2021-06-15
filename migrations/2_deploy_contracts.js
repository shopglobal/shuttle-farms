const ShuttleTokenArtifact = artifacts.require("ShuttleToken");
const MasterEngineer = artifacts.require("MasterEngineer");

// placeholder values
var devAddress = "0xAAD148340CA7d2dD8Aa0DB9F0d9886d6ec1ac847"
var shuttlePerBlock = 10
var startBlock = 100000
var feeAddress = "0x2184F5837B44e1dCA72cDd4bfb91b6305569D1B5"

module.exports = async function(deployer, network, accounts) {

  await deployer.deploy(ShuttleTokenArtifact);

  var shuttleTokenContract = await ShuttleTokenArtifact.deployed();
  var masterEngineerContract = await deployer.deploy(
          MasterEngineer,
          shuttleTokenContract.address,
          devAddress,
          feeAddress,
          shuttlePerBlock,
          startBlock
      );
}