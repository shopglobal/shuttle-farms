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
});