// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./ShuttleToken.sol";

// MasterEngineer is the engineer of Shuttle. He can build Shuttle and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SHUTTLE is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterEngineer is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SHUTTLEs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accShuttlePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accShuttlePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SHUTTLEs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SHUTTLEs distribution occurs.
        uint256 accShuttlePerShare;   // Accumulated SHUTTLEs per share, times 1e12. See below.
        uint16 withdrawFeeBP;      // Deposit fee in basis points
    }

    // The SHUTTLE TOKEN!
    ShuttleToken public shuttle;
    // Dev address.
    address public devaddr;
    // SHUTTLE tokens created per block.
    uint256 public shuttlePerBlock;
    // Bonus muliplier for early shuttle makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // placeholder values

    // Minimum emission rate: 0.1 SHUTTLE per block.
    uint256 public constant MINIMUM_EMISSION_RATE = 100 finney;
    // Suppose BSC block time is 3 sec, then 3 sec x 15000 block ~ 13 hours
    uint256 public constant EMISSION_REDUCTION_PERIOD_BLOCKS = 15000;
    // Emission reduction rate should rise proportionally with emission reduction rate
    uint256 public constant EMISSION_REDUCTION_RATE_PER_PERIOD = 500; // 5%
    // Last reduction period index
    uint256 public lastReductionPeriodIndex = 0;

    // end of placeholder values
    
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SHUTTLE mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateCustomEmissionRate(address indexed user, uint256 shuttlePerBlock);
    event UpdateEmissionRate(address indexed caller, uint256 previousAmount, uint256 newAmount);

    constructor(
        ShuttleToken _shuttle,
        address _devaddr,
        address _feeAddress,
        uint256 _shuttlePerBlock,
        uint256 _startBlock
    ) public {
        shuttle = _shuttle;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        shuttlePerBlock = _shuttlePerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _withdrawFeeBP, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(_withdrawFeeBP <= 200, "add: invalid withdraw fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accShuttlePerShare : 0,
        withdrawFeeBP : _withdrawFeeBP
        }));
    }

    // Update the given pool's SHUTTLE allocation point and withdraw fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _withdrawFeeBP, bool _withUpdate) public onlyOwner {
        require(_withdrawFeeBP <= 200, "set: invalid withdraw fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].withdrawFeeBP = _withdrawFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending SHUTTLEs on frontend.
    function pendingShuttle(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accShuttlePerShare = pool.accShuttlePerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 shuttleReward = multiplier.mul(shuttlePerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accShuttlePerShare = accShuttlePerShare.add(shuttleReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accShuttlePerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 shuttleReward = multiplier.mul(shuttlePerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        shuttle.mint(devaddr, shuttleReward.div(10));
        shuttle.mint(address(this), shuttleReward);
        pool.accShuttlePerShare = pool.accShuttlePerShare.add(shuttleReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for SHUTTLE allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accShuttlePerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeShuttleTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accShuttlePerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accShuttlePerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeShuttleTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            if (pool.withdrawFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.withdrawFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.sub(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.sub(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accShuttlePerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe shuttle transfer function, just in case if rounding error causes pool to not have enough SHUTTLEs.
    function safeShuttleTransfer(address _to, uint256 _amount) internal {
        uint256 shuttleBal = shuttle.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > shuttleBal) {
            transferSuccess = shuttle.transfer(_to, shuttleBal);
        } else {
            transferSuccess = shuttle.transfer(_to, _amount);
        }
        require(transferSuccess, "safeShuttleTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    // Reduce emission rate by 3% every 9,600 blocks ~ 8hours. This function can be called publicly.
    function updateEmissionRate() public {
        require(block.number > startBlock, "updateEmissionRate: Can only be called after mining starts");
        require(shuttlePerBlock > MINIMUM_EMISSION_RATE, "updateEmissionRate: Emission rate has reached the minimum threshold");

        uint256 currentIndex = block.number.sub(startBlock).div(EMISSION_REDUCTION_PERIOD_BLOCKS);
        if (currentIndex <= lastReductionPeriodIndex) {
            return;
        }

        uint256 newEmissionRate = shuttlePerBlock;
        for (uint256 index = lastReductionPeriodIndex; index < currentIndex; ++index) {
            newEmissionRate = newEmissionRate.mul(1e4 - EMISSION_REDUCTION_RATE_PER_PERIOD).div(1e4);
        }

        newEmissionRate = newEmissionRate < MINIMUM_EMISSION_RATE ? MINIMUM_EMISSION_RATE : newEmissionRate;
        if (newEmissionRate >= shuttlePerBlock) {
            return;
        }

        massUpdatePools();
        lastReductionPeriodIndex = currentIndex;
        uint256 previousEmissionRate = shuttlePerBlock;
        shuttlePerBlock = newEmissionRate;
        emit UpdateEmissionRate(msg.sender, previousEmissionRate, newEmissionRate);
    }

      //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateCustomEmissionRate(uint256 _shuttlePerBlock) public onlyOwner {
        massUpdatePools();
        shuttlePerBlock = _shuttlePerBlock;
        emit UpdateCustomEmissionRate(msg.sender, _shuttlePerBlock);
    }

}
