const ShuttleTokenArtifact = artifacts.require("ShuttleToken");
const MasterEngineer = artifacts.require("MasterEngineer");

// placeholder values
var devAddress = ""
var shuttlePerBlock = 10
var startBlock = 100000

module.exports = async function(deployer, network, accounts) {
  await deployer.deploy(ShuttleTokenArtifact);

  var shuttleTokenContract = await ShuttleTokenArtifact.deployed();
  var masterEngineerContract = await deployer.deploy(
          MasterEngineer,
          shuttleTokenContract.address,
          devAddress,
          shuttlePerBlock,
          startBlock
      );
}