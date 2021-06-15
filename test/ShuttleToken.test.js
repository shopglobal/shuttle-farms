const { assert } = require("chai");

const ShuttleToken = artifacts.require('ShuttleToken');

contract('ShuttleToken', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.shuttle = await ShuttleToken.new({ from: minter });
    });


    it('mint', async () => {
        await this.shuttle.mint(alice, 1000, { from: minter });
        assert.equal((await this.shuttle.balanceOf(alice)).toString(), '1000');
    })

    it('tax transfered', async () => {
    	await this.shuttle.mint(alice, 100000000, { from: minter });
    	await this.shuttle.increaseAllowance(alice, 100); 
    	await this.shuttle.transferFrom(alice, bob, 100);
    	assert.equal((await this.shuttle.balanceOf(bob)).toString(), '95');
    })
});