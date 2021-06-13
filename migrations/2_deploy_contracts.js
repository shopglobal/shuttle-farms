const ShuttleTokenArtifact = artifacts.require("ShuttleToken");
const MasterEngineer = artifacts.require("MasterEngineer");

// placeholder values
var devAddress = "0xFE13769B6118b3e5fb1f9C8b8208E39abb980987"
var shuttlePerBlock = 10
var startBlock = 100000
var feeAddress = "0x8bab8bf1e45e9cc78aa128C62c7f5Afd7B8112aD"

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