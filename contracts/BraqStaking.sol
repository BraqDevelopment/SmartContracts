// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/**
 * @title Braq Staking Contract
 * @notice Stake BraqToken across four different pools that release hourly rewards
 * @author Cosmodude, HorizenLabs
 */
contract BraqTokenStaking is Ownable {

    using SafeCast for uint256;
    using SafeCast for int256;

    /// @notice State for BraqToken, BraqFriends, BraqMonsters, and Pair Pools
    struct Pool {
        uint48 lastRewardedTimestampHour;
        uint16 lastRewardsRangeIndex;
        uint96 stakedAmount;
        uint96 accumulatedRewardsPerShare;
        TimeRange[] timeRanges;
    }

    /// @notice Pool rules valid for a given duration of time.
    /// @dev All TimeRange timestamp values must represent whole hours
    struct TimeRange {
        uint48 startTimestampHour;
        uint48 endTimestampHour;
        uint96 rewardsPerHour;
        uint96 capPerPosition;
    }

    /// @dev Convenience struct for front-end applications
    struct PoolUI {
        uint256 poolId;
        uint256 stakedAmount;
        TimeRange currentTimeRange;
    }

    /// @dev Per address amount and reward tracking
    struct Position {
        uint256 stakedAmount;
        int256 rewardsDebt;
    }
    mapping (address => Position) public addressPosition;

    /// @dev Struct for depositing and withdrawing from the BraqFriends and BraqMonsters NFT pools
    struct SingleNft {
        uint32 tokenId;
        uint224 amount;
    }
    /// @dev Struct for depositing into the Pair pool
    struct PairNftDepositWithAmount {
        uint32 friendTokenId;
        uint32 monsterTokenId;
        uint184 amount;
    }
    /// @dev Struct for withdrawing from Pair pool
    struct PairNftWithdrawWithAmount {
        uint32 friendTokenId;
        uint32 monsterTokenId;
        uint184 amount;
        bool isUncommit;
    }
    /// @dev Struct for claiming from an NFT pool
    struct PairNft {
        uint128 friendTokenId;
        uint128 monsterTokenId;
    }
    /// @dev NFT paired status.  Can be used bi-directionally (BraqFriends -> BraqMonsters) or (BraqMonsters -> BraqFriends)
    struct PairingStatus {
        uint248 tokenId;
        bool isPaired;
    }

    // @dev UI focused payload
    struct DashboardStake {
        uint256 poolId;
        uint256 tokenId;
        uint256 deposited;
        uint256 unclaimed;
        uint256 rewards24hr;
        DashboardPair pair;
    }
    /// @dev Sub struct for DashboardStake
    struct DashboardPair {
        uint256 mainTokenId;
        uint256 mainTypePoolId;
    }
    /// @dev Placeholder for pair status, used by BraqToken Pool
    DashboardPair private NULL_PAIR = DashboardPair(0, 0);

    /// @notice Internal BraqToken amount for distributing staking reward claims
    IERC20 public immutable braqToken;
    uint256 private constant BRAQ_TOKEN_PRECISION = 1e18;
    uint256 private constant MIN_DEPOSIT = 100 * BRAQ_TOKEN_PRECISION;
    uint256 private constant SECONDS_PER_HOUR = 3600;
    uint256 private constant SECONDS_PER_MINUTE = 60;

    uint256 constant BraqToken_POOL_ID = 0;
    uint256 constant BraqFriends_POOL_ID = 1;
    uint256 constant BraqMonsters_POOL_ID = 2;
    uint256 constant Pair_POOL_ID = 3;
    Pool[4] public pools;

    /// @dev NFT contract mapping per pool
    mapping(uint256 => ERC721Enumerable) public nftContracts;
    /// @dev poolId => tokenId => nft position
    mapping(uint256 => mapping(uint256 => Position)) public nftPosition;
    /// @dev Friends token ID => monster token ID
    mapping(uint256 => PairingStatus) public FriendToMonster;
    /// @dev Monster Token ID => Friends token ID
    mapping(uint256 => PairingStatus) public MonsterToFriend;

    /** Custom Events */
    event UpdatePool(
        uint256 indexed poolId,
        uint256 lastRewardedBlock,
        uint256 stakedAmount,
        uint256 accumulatedRewardsPerShare
    );
    event Deposit(
        address indexed user,
        uint256 amount,
        address recipient
    );
    event DepositNft(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 tokenId
    );
    event DepositPairNft(
        address indexed user,
        uint256 amount,
        uint256 FriendsTokenId,
        uint256 MonstersTokenId
    );
    event Withdraw(
        address indexed user,
        uint256 amount,
        address recipient
    );
    event WithdrawNft(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        address recipient,
        uint256 tokenId
    );
    event WithdrawPairNft(
        address indexed user,
        uint256 amount,
        uint256 FriendsTokenId,
        uint256 MonstersTokenId
    );
    event ClaimRewards(
        address indexed user,
        uint256 amount,
        address recipient
    );
    event ClaimRewardsNft(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 tokenId
    );
    event ClaimRewardsPairNft(
        address indexed user,
        uint256 amount,
        uint256 FriendsTokenId,
        uint256 MonstersTokenId
    );

    error DepositMoreThanOneBraq();
    error InvalidPoolId();
    error StartMustBeGreaterThanEnd();
    error StartNotWholeHour();
    error EndNotWholeHour();
    error StartMustEqualLastEnd();
    error CallerNotOwner();
    error MainTokenNotOwnedOrPaired();
    error MonsterNotOwnedOrPaired();
    error MonsterAlreadyPaired();
    error ExceededCapAmount();
    error NotOwnerOfFriend();
    error NotOwnerOfMonster();
    error ProvidedTokensNotPaired();
    error ExceededStakedAmount();
    error NeitherTokenInPairOwnedByCaller();
    error SplitPairCantPartiallyWithdraw();
    error UncommitWrongParameters();

    /**
     * @notice Construct a new BraqTokenStaking instance
     * @param _braqTokenContractAddress The BraqToken ERC20 contract address
     * @param _friendsContractAddress The BraqFriends NFT contract address
     * @param _monstersContractAddress The BraqMonsters NFT contract address
     */
    constructor(
        address _braqTokenContractAddress,
        address _friendsContractAddress,
        address _monstersContractAddress
    ) {
        braqToken = IERC20(_braqTokenContractAddress);
        nftContracts[BraqFriends_POOL_ID] = ERC721Enumerable(_friendsContractAddress);
        nftContracts[BraqMonsters_POOL_ID] = ERC721Enumerable(_monstersContractAddress);
    }

    // Deposit/Commit Methods

    /**
     * @notice Deposit BraqToken to the BraqToken Pool
     * @param _amount Amount in BraqToken
     * @param _recipient Address the deposit it stored to
     * @dev BraqToken deposit must be >= 100 BraqToken
     */
    function depositBraqToken(uint256 _amount, address _recipient) public {
        if (_amount < MIN_DEPOSIT) revert DepositMoreThanOneBraq();
        updatePool(BraqToken_POOL_ID);

        Position storage position = addressPosition[_recipient];
        _deposit(BraqToken_POOL_ID, position, _amount);

        braqToken.transferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount, _recipient);
    }

    /**
     * @notice Deposit BraqToken to the BraqToken Pool
     * @param _amount Amount in BraqToken
     * @dev Deposit on behalf of msg.sender. BraqToken deposit must be >= 100 BraqToken
     */
    function depositSelfBraqToken(uint256 _amount) external {
        depositBraqToken(_amount, msg.sender);
    }

    /**
     * @notice Deposit BraqToken to the Friends Pool
     * @param _nfts Array of SingleNft structs
     * @dev Commits 1 or more BraqFriends NFTs, each with a BraqToken amount to the Friends pool.\
     * Each BraqFriend committed must attach an BraqToken amount >= 100 BraqToken and <= the BraqFriends pool cap amount.
     */
    function depositBraqFriends(SingleNft[] calldata _nfts) external {
        _depositNft(BraqFriends_POOL_ID, _nfts);
    }

    /**
     * @notice Deposit BraqToken to the BraqMonsters Pool
     * @param _nfts Array of SingleNft structs
     * @dev Commits 1 or more BraqMonsters NFTs, each with an BraqToken amount to the Monsters pool.\
     * Each Monster committed must attach an BraqToken amount >= 100 BraqToken and <= the Monsters pool cap amount.
     */
    function depositBraqMonster(SingleNft[] calldata _nfts) external {
        _depositNft(BraqMonsters_POOL_ID, _nfts);
    }

    /**
     * @notice Deposit BraqToken to the Pair Pool, where Pair = Friend + Monster
     * @param _Pairs Array of PairNftDepositWithAmount structs
     * @dev Commits 1 or more Pairs, each with an BraqToken amount to the Pair pool.\
     * Each Pair committed must attach an BraqToken amount >= 100 BraqToken and <= the Pair pool cap amount.\
     * Example : Friend + Monster + 100 BraqToken:  [[1, 1, "100000000000000000000"],[]]\
     */
    function depositPair(PairNftDepositWithAmount[] calldata _Pairs) external {
        updatePool(Pair_POOL_ID);
        _depositPairNft(_Pairs);
    }

    // Claim Rewards Methods

    /**
     * @notice Claim rewards for msg.sender and send to recipient
     * @param _recipient Address to send claim reward to
     */
    function claimBraqToken(address _recipient) public {
        updatePool(BraqToken_POOL_ID);

        Position storage position = addressPosition[msg.sender];
        uint256 rewardsToBeClaimed = _claim(BraqToken_POOL_ID, position, _recipient);

        emit ClaimRewards(msg.sender, rewardsToBeClaimed, _recipient);
    }

    /// @notice Claim and send rewards
    function claimSelfBraqToken() external {
        claimBraqToken(msg.sender);
    }

    /**
     * @notice Claim rewards for array of Friends NFTs and send to recipient
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimFriends(uint256[] calldata _nfts, address _recipient) external {
        _claimNft(BraqFriends_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Claim rewards for array of BraqFriends NFTs
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     */
    function claimSelfFriends(uint256[] calldata _nfts) external {
        _claimNft(BraqFriends_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Claim rewards for array of BraqMonsters NFTs and send to recipient
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimMonsters(uint256[] calldata _nfts, address _recipient) external {
        _claimNft(BraqMonsters_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Claim rewards for array of BraqMonsters NFTs
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     */
    function claimSelfMonsters(uint256[] calldata _nfts) external {
        _claimNft(BraqMonsters_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Claim rewards for array of Paired NFTs and send to recipient
     * @param _Pairs Array of Paired NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimPair(PairNft[] calldata _Pairs, address _recipient) public {
        updatePool(Pair_POOL_ID);
        _claimPairNft(_Pairs, _recipient);
    }

    /**
     * @notice Claim rewards for array of Paired NFTs
     * @param _Pairs Array of Paired NFTs owned and committed by the msg.sender
     */
    function claimSelfPair(PairNft[] calldata _Pairs) external {
        claimPair(_Pairs, msg.sender);
    }

    // Uncommit/Withdraw Methods

    /**
     * @notice Withdraw staked BraqToken from the BraqToken pool. Performs an automatic claim as part of the withdraw process.
     * @param _amount Amount of BraqToken
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawBraqToken(uint256 _amount, address _recipient) public {
        updatePool(BraqToken_POOL_ID);

        Position storage position = addressPosition[msg.sender];
        if (_amount == position.stakedAmount) {
            uint256 rewardsToBeClaimed = _claim(BraqToken_POOL_ID, position, _recipient);
            emit ClaimRewards(msg.sender, rewardsToBeClaimed, _recipient);
        }
        _withdraw(BraqToken_POOL_ID, position, _amount);

        braqToken.transfer(_recipient, _amount);

        emit Withdraw(msg.sender, _amount, _recipient);
    }

    /**
     * @notice Withdraw staked BraqToken from the BraqToken pool. If withdraw is total staked amount, performs an automatic claim.
     * @param _amount Amount of BraqToken
     */
    function withdrawSelfBraqToken(uint256 _amount) external {
        withdrawBraqToken(_amount, msg.sender);
    }

    /**
     * @notice Withdraw staked BraqToken from the BraqFriends pool. If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of BraqFriends NFT's with staked amounts
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawFriends(SingleNft[] calldata _nfts, address _recipient) external {
        _withdrawNft(BraqFriends_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Withdraw staked BraqToken from the BraqFriends pool. If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of BraqFriends NFT's with staked amounts
     */
    function withdrawSelfFriends(SingleNft[] calldata _nfts) external {
        _withdrawNft(BraqFriends_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Withdraw staked BraqToken from the BraqMonsters pool. If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of BraqMonsters NFT's with staked amounts
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawMonsters(SingleNft[] calldata _nfts, address _recipient) external {
        _withdrawNft(BraqMonsters_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Withdraw staked BraqToken from the BraqMonsters pool. If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of BraqMonsters NFT's with staked amounts
     */
    function withdrawSelfMonsters(SingleNft[] calldata _nfts) external {
        _withdrawNft(BraqMonsters_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Withdraw staked BraqToken from the Pair pool. If withdraw is total staked amount, performs an automatic claim.
     * @param _Pairs Array of Paired NFT's with staked amounts and isUncommit boolean
     * @dev if pairs have split ownership and BraqMonster is attempting a withdraw, the withdraw must be for the total staked amount
     */
    function withdrawPair(PairNftWithdrawWithAmount[] calldata _Pairs) external {
        updatePool(Pair_POOL_ID);
        _withdrawPairNft(_Pairs);
    }

    // Time Range Methods

    /**
     * @notice Add single time range with a given rewards per hour for a given pool
     * @dev In practice one Time Range will represent one quarter (defined by `_startTimestamp`and `_endTimeStamp` as whole hours)
     * where the rewards per hour is constant for a given pool.
     * @param _poolId Available pool values 0-3
     * @param _amount Total amount of BraqToken to be distributed over the range
     * @param _startTimestamp Whole hour timestamp representation
     * @param _endTimeStamp Whole hour timestamp representation
     * @param _capPerPosition Per position cap amount determined by poolId
     */
    function addTimeRange(
        uint256 _poolId,
        uint256 _amount,
        uint256 _startTimestamp,
        uint256 _endTimeStamp,
        uint256 _capPerPosition) external onlyOwner
    {
        if (_poolId > Pair_POOL_ID) revert InvalidPoolId();
        if (_startTimestamp >= _endTimeStamp) revert StartMustBeGreaterThanEnd();
        if (getMinute(_startTimestamp) > 0 || getSecond(_startTimestamp) > 0) revert StartNotWholeHour();
        if (getMinute(_endTimeStamp) > 0 || getSecond(_endTimeStamp) > 0) revert EndNotWholeHour();

        Pool storage pool = pools[_poolId];
        uint256 length = pool.timeRanges.length;
        if (length > 0) {
            if (_startTimestamp != pool.timeRanges[length - 1].endTimestampHour) revert StartMustEqualLastEnd();
        }

        uint256 hoursInSeconds = _endTimeStamp - _startTimestamp;
        uint256 rewardsPerHour = _amount * SECONDS_PER_HOUR / hoursInSeconds;

        TimeRange memory next = TimeRange(_startTimestamp.toUint48(), _endTimeStamp.toUint48(),
            rewardsPerHour.toUint96(), _capPerPosition.toUint96());
        pool.timeRanges.push(next);
    }

    /**
     * @notice Removes the last Time Range for a given pool.
     * @param _poolId Available pool values 0-3
     */
    function removeLastTimeRange(uint256 _poolId) external onlyOwner {
        pools[_poolId].timeRanges.pop();
    }

    /**
     * @notice Lookup method for a TimeRange struct
     * @return TimeRange A Pool's timeRanges struct by index.
     * @param _poolId Available pool values 0-3
     * @param _index Target index in a Pool's timeRanges array
     */
    function getTimeRangeBy(uint256 _poolId, uint256 _index) public view returns (TimeRange memory) {
        return pools[_poolId].timeRanges[_index];
    }

    // Pool Methods

    /**
     * @notice Lookup available rewards for a pool over a given time range
     * @return uint256 The amount of BraqToken rewards to be distributed by pool for a given time range
     * @return uint256 The amount of time ranges
     * @param _poolId Available pool values 0-3
     * @param _from Whole hour timestamp representation
     * @param _to Whole hour timestamp representation
     */
    function rewardsBy(uint256 _poolId, uint256 _from, uint256 _to) public view returns (uint256, uint256) {
        Pool memory pool = pools[_poolId];

        uint256 currentIndex = pool.lastRewardsRangeIndex;
        if(_to < pool.timeRanges[0].startTimestampHour) return (0, currentIndex);

        while(_from > pool.timeRanges[currentIndex].endTimestampHour && _to > pool.timeRanges[currentIndex].endTimestampHour) {
            unchecked {
                ++currentIndex;
            }
        }

        uint256 rewards;
        TimeRange memory current;
        uint256 startTimestampHour;
        uint256 endTimestampHour;
        uint256 length = pool.timeRanges.length;
        for(uint256 i = currentIndex; i < length;) {
            current = pool.timeRanges[i];
            startTimestampHour = _from <= current.startTimestampHour ? current.startTimestampHour : _from;
            endTimestampHour = _to <= current.endTimestampHour ? _to : current.endTimestampHour;

            rewards = rewards + (endTimestampHour - startTimestampHour) * current.rewardsPerHour / SECONDS_PER_HOUR;

            if(_to <= endTimestampHour) {
                return (rewards, i);
            }
            unchecked {
                ++i;
            }
        }

        return (rewards, length - 1);
    }

    /**
     * @notice Updates reward variables `lastRewardedTimestampHour`, `accumulatedRewardsPerShare` and `lastRewardsRangeIndex`
     * for a given pool.
     * @param _poolId Available pool values 0-3
     */
    function updatePool(uint256 _poolId) public {
        Pool storage pool = pools[_poolId];

        if (block.timestamp < pool.timeRanges[0].startTimestampHour) return;
        if (block.timestamp <= pool.lastRewardedTimestampHour + SECONDS_PER_HOUR) return;

        uint48 lastTimestampHour = pool.timeRanges[pool.timeRanges.length-1].endTimestampHour;
        uint48 previousTimestampHour = getPreviousTimestampHour().toUint48();

        if (pool.stakedAmount == 0) {
            pool.lastRewardedTimestampHour = previousTimestampHour > lastTimestampHour ? lastTimestampHour : previousTimestampHour;
            return;
        }

        (uint256 rewards, uint256 index) = rewardsBy(_poolId, pool.lastRewardedTimestampHour, previousTimestampHour);
        if (pool.lastRewardsRangeIndex != index) {
            pool.lastRewardsRangeIndex = index.toUint16();
        }
        // amount of rewards per token
        pool.accumulatedRewardsPerShare = (pool.accumulatedRewardsPerShare + (rewards * BRAQ_TOKEN_PRECISION) / pool.stakedAmount).toUint96();
        pool.lastRewardedTimestampHour = previousTimestampHour > lastTimestampHour ? lastTimestampHour : previousTimestampHour;

        emit UpdatePool(_poolId, pool.lastRewardedTimestampHour, pool.stakedAmount, pool.accumulatedRewardsPerShare);
    }

    // Read Methods

    function getCurrentTimeRangeIndex(Pool memory pool) private view returns (uint256) {
        uint256 current = pool.lastRewardsRangeIndex;

        if (block.timestamp < pool.timeRanges[current].startTimestampHour) return current;
        for(current = pool.lastRewardsRangeIndex; current < pool.timeRanges.length; ++current) {
            TimeRange memory currentTimeRange = pool.timeRanges[current];
            if (currentTimeRange.startTimestampHour <= block.timestamp && block.timestamp <= currentTimeRange.endTimestampHour) return current;
        }
        revert("distribution ended");
    }

    /**
     * @notice Fetches a PoolUI struct (poolId, stakedAmount, currentTimeRange) for each reward pool
     * @return PoolUI for BraqToken.
     * @return PoolUI for BraqFriends.
     * @return PoolUI for BraqMonsters.
     * @return PoolUI for Pair.
     */
    function getPoolsUI() public view returns (PoolUI memory, PoolUI memory, PoolUI memory, PoolUI memory) {
        Pool memory braqTokenPool = pools[0];
        Pool memory braqFriendsPool = pools[1];
        Pool memory braqMonstersPool = pools[2];
        Pool memory PairPool = pools[3];
        uint256 current = getCurrentTimeRangeIndex(braqTokenPool);
        return (PoolUI(0,braqTokenPool.stakedAmount, braqTokenPool.timeRanges[current]),
                PoolUI(1,braqFriendsPool.stakedAmount, braqFriendsPool.timeRanges[current]),
                PoolUI(2,braqMonstersPool.stakedAmount, braqMonstersPool.timeRanges[current]),
                PoolUI(3,PairPool.stakedAmount, PairPool.timeRanges[current]));
    }

    /**
     * @notice Fetches an address total staked amount, used by voting contract
     * @return amount uint256 staked amount for all pools.
     * @param _address An Ethereum address
     */
    function stakedTotal(address _address) external view returns (uint256) {
        uint256 total = addressPosition[_address].stakedAmount;

        total += _stakedTotal(BraqFriends_POOL_ID, _address);
        total += _stakedTotal(BraqMonsters_POOL_ID, _address);
        total += _stakedTotalPair(_address);

        return total;
    }

    function _stakedTotal(uint256 _poolId, address _addr) private view returns (uint256) {
        uint256 total = 0;
        uint256 nftCount = nftContracts[_poolId].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 tokenId = nftContracts[_poolId].tokenOfOwnerByIndex(_addr, i);
            total += nftPosition[_poolId][tokenId].stakedAmount;
        }

        return total;
    }

    function _stakedTotalPair(address _addr) private view returns (uint256) {
        uint256 total = 0;

        uint256 nftCount = nftContracts[BraqFriends_POOL_ID].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 friendTokenId = nftContracts[BraqFriends_POOL_ID].tokenOfOwnerByIndex(_addr, i);
            if (FriendToMonster[friendTokenId].isPaired) {
                total += nftPosition[BraqFriends_POOL_ID][friendTokenId].stakedAmount;
            }
        }

        nftCount = nftContracts[BraqMonsters_POOL_ID].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 monsterTokenId = nftContracts[BraqMonsters_POOL_ID].tokenOfOwnerByIndex(_addr, i);
            if (MonsterToFriend[monsterTokenId].isPaired) {
                total += nftPosition[BraqMonsters_POOL_ID][monsterTokenId].stakedAmount;
            }
        }

        return total;
    }

    /**
     * @notice Fetches a DashboardStake = [poolId, tokenId, deposited, unclaimed, rewards24Hrs, paired] \
     * for each pool, for an Ethereum address
     * @return dashboardStakes An array of DashboardStake structs
     * @param _address An Ethereum address
     */
    function getAllStakes(address _address) public view returns (DashboardStake[] memory) {

        DashboardStake memory braqTokenStake = getBraqTokenStake(_address);
        DashboardStake[] memory friendsStakes = getFriendsStakes(_address);
        DashboardStake[] memory monsterStakes = getMonstersStakes(_address);
        DashboardStake[] memory pairStakes = getPairStakes(_address);
        DashboardStake[] memory splitStakes = getSplitStakes(_address);

        uint256 count = (friendsStakes.length + monsterStakes.length + pairStakes.length + splitStakes.length + 1);
        DashboardStake[] memory allStakes = new DashboardStake[](count);

        uint256 offset = 0;
        allStakes[offset] = braqTokenStake;
        ++offset;

        for(uint256 i = 0; i < friendsStakes.length; ++i) {
            allStakes[offset] = friendsStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < monsterStakes.length; ++i) {
            allStakes[offset] = monsterStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < pairStakes.length; ++i) {
            allStakes[offset] = pairStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < splitStakes.length; ++i) {
            allStakes[offset] = splitStakes[i];
            ++offset;
        }

        return allStakes;
    }

    /**
     * @notice Fetches a DashboardStake for the BraqToken pool
     * @return dashboardStake A dashboardStake struct
     * @param _address An Ethereum address
     */
    function getBraqTokenStake(address _address) public view returns (DashboardStake memory) {
        uint256 tokenId = 0;
        uint256 deposited = addressPosition[_address].stakedAmount;
        uint256 unclaimed = deposited > 0 ? this.pendingRewards(0, _address, tokenId) : 0;
        uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(0, _address, 0) : 0;

        return DashboardStake(BraqToken_POOL_ID, tokenId, deposited, unclaimed, rewards24Hrs, NULL_PAIR);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the BraqFriends pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getFriendsStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, BraqFriends_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the BraqMonsters pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getMonstersStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, BraqMonsters_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the Pair pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getPairStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, Pair_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the Pair Pool when ownership is split \
     * ie BraqFriends and BraqMonsters in pair pool have different owners.
     * @return dashboardStakes An array of DashboardStake structs
     * @param _address An Ethereum address
     */
    function getSplitStakes(address _address) public view returns (DashboardStake[] memory) {
        uint256 friendsSplits = _getSplitStakeCount(nftContracts[BraqFriends_POOL_ID].balanceOf(_address), _address);
        uint256 monstersSplits = _getSplitStakeCount(nftContracts[BraqMonsters_POOL_ID].balanceOf(_address), _address);
        uint256 totalSplits = friendsSplits + monstersSplits;

        if(totalSplits == 0) {
            return new DashboardStake[](0);
        }

        DashboardStake[] memory friendsSplitStakes = _getSplitStakes(friendsSplits, _address);
        DashboardStake[] memory monsterSplitStakes = _getSplitStakes(monstersSplits, _address);

        DashboardStake[] memory splitStakes = new DashboardStake[](totalSplits);
        uint256 offset = 0;
        for(uint256 i = 0; i < friendsSplitStakes.length; ++i) {
            splitStakes[offset] = friendsSplitStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < monsterSplitStakes.length; ++i) {
            splitStakes[offset] = monsterSplitStakes[i];
            ++offset;
        }

        return splitStakes;
    }

    function _getSplitStakes(uint256 splits, address _address) private view returns (DashboardStake[] memory) {

        DashboardStake[] memory dashboardStakes = new DashboardStake[](splits);
        uint256 counter;

        for(uint256 i = 0; i < nftContracts[BraqFriends_POOL_ID].balanceOf(_address); ++i) {
            uint256 mainTokenId = nftContracts[BraqFriends_POOL_ID].tokenOfOwnerByIndex(_address, i);
            if(FriendToMonster[mainTokenId].isPaired) {
                uint256 minorTokenId = FriendToMonster[mainTokenId].tokenId;
                address currentOwner = nftContracts[Pair_POOL_ID].ownerOf(minorTokenId);

                /* Split Pair Check*/
                if (currentOwner != _address) {
                    uint256 deposited = nftPosition[Pair_POOL_ID][minorTokenId].stakedAmount;
                    uint256 unclaimed = deposited > 0 ? this.pendingRewards(Pair_POOL_ID, currentOwner, minorTokenId) : 0;
                    uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(Pair_POOL_ID, currentOwner, minorTokenId): 0;

                    DashboardPair memory pair = NULL_PAIR;
                    if(MonsterToFriend[minorTokenId].isPaired) {
                        pair = DashboardPair(MonsterToFriend[minorTokenId].tokenId, BraqFriends_POOL_ID);
                    }

                    DashboardStake memory dashboardStake = DashboardStake(Pair_POOL_ID, minorTokenId, deposited, unclaimed, rewards24Hrs, pair);
                    dashboardStakes[counter] = dashboardStake;
                    ++counter;
                }
            }
        }

        return dashboardStakes;
    }

    function _getSplitStakeCount(uint256 nftCount, address _address) private view returns (uint256) {
        uint256 splitCount;
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 mainTokenId = nftContracts[BraqFriends_POOL_ID].tokenOfOwnerByIndex(_address, i);
            if(FriendToMonster[mainTokenId].isPaired) {
                uint256 minorTokenId = FriendToMonster[mainTokenId].tokenId;
                address currentOwner = nftContracts[Pair_POOL_ID].ownerOf(minorTokenId);
                if (currentOwner != _address) {
                    ++splitCount;
                }
            }
        }

        return splitCount;
    }

    function _getStakes(address _address, uint256 _poolId) private view returns (DashboardStake[] memory) {
        uint256 nftCount = nftContracts[_poolId].balanceOf(_address);
        DashboardStake[] memory dashboardStakes = nftCount > 0 ? new DashboardStake[](nftCount) : new DashboardStake[](0);

        if(nftCount == 0) {
            return dashboardStakes;
        }

        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 tokenId = nftContracts[_poolId].tokenOfOwnerByIndex(_address, i);
            uint256 deposited = nftPosition[_poolId][tokenId].stakedAmount;
            uint256 unclaimed = deposited > 0 ? this.pendingRewards(_poolId, _address, tokenId) : 0;
            uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(_poolId, _address, tokenId): 0;

            DashboardPair memory pair = NULL_PAIR;
            if(_poolId == Pair_POOL_ID) {
                if(MonsterToFriend[tokenId].isPaired) {
                    pair = DashboardPair(MonsterToFriend[tokenId].tokenId, BraqFriends_POOL_ID);
                } else if(MonsterToFriend[tokenId].isPaired) {
                    pair = DashboardPair(MonsterToFriend[tokenId].tokenId, BraqMonsters_POOL_ID);
                }
            }

            DashboardStake memory dashboardStake = DashboardStake(_poolId, tokenId, deposited, unclaimed, rewards24Hrs, pair);
            dashboardStakes[i] = dashboardStake;
        }

        return dashboardStakes;
    }

    function _estimate24HourRewards(uint256 _poolId, address _address, uint256 _tokenId) private view returns (uint256) {
        Pool memory pool = pools[_poolId];
        Position memory position = _poolId == 0 ? addressPosition[_address]: nftPosition[_poolId][_tokenId];

        TimeRange memory rewards = getTimeRangeBy(_poolId, pool.lastRewardsRangeIndex);
        return (position.stakedAmount * uint256(rewards.rewardsPerHour) * 24) / uint256(pool.stakedAmount);
    }

    /**
     * @notice Fetches the current amount of claimable BraqToken rewards for a given position from a given pool.
     * @return uint256 value of pending rewards
     * @param _poolId Available pool values 0-3
     * @param _address Address to lookup Position for
     * @param _tokenId An NFT id
     */
    function pendingRewards(uint256 _poolId, address _address, uint256 _tokenId) external view returns (uint256) {
        Pool memory pool = pools[_poolId];
        Position memory position = _poolId == 0 ? addressPosition[_address]: nftPosition[_poolId][_tokenId];

        (uint256 rewardsSinceLastCalculated,) = rewardsBy(_poolId, pool.lastRewardedTimestampHour, getPreviousTimestampHour());
        uint256 accumulatedRewardsPerShare = pool.accumulatedRewardsPerShare;

        if (block.timestamp > pool.lastRewardedTimestampHour + SECONDS_PER_HOUR && pool.stakedAmount != 0) {
            accumulatedRewardsPerShare = accumulatedRewardsPerShare + rewardsSinceLastCalculated * BRAQ_TOKEN_PRECISION / pool.stakedAmount;
        }
        return ((position.stakedAmount * accumulatedRewardsPerShare).toInt256() - position.rewardsDebt).toUint256() / BRAQ_TOKEN_PRECISION;
    }

    // Convenience methods for timestamp calculation

    /// @notice the minutes (0 to 59) of a timestamp
    function getMinute(uint256 timestamp) internal pure returns (uint256 minute) {
        uint256 secs = timestamp % SECONDS_PER_HOUR;
        minute = secs / SECONDS_PER_MINUTE;
    }

    /// @notice the seconds (0 to 59) of a timestamp
    function getSecond(uint256 timestamp) internal pure returns (uint256 second) {
        second = timestamp % SECONDS_PER_MINUTE;
    }

    /// @notice the previous whole hour of a timestamp
    function getPreviousTimestampHour() internal view returns (uint256) {
        return block.timestamp - (getMinute(block.timestamp) * 60 + getSecond(block.timestamp));
    }

    // Private Methods - shared logic
    function _deposit(uint256 _poolId, Position storage _position, uint256 _amount) private {
        Pool storage pool = pools[_poolId];

        _position.stakedAmount += _amount;
        pool.stakedAmount += _amount.toUint96();
        _position.rewardsDebt += (_amount * pool.accumulatedRewardsPerShare).toInt256();
    }

    function _depositNft(uint256 _poolId, SingleNft[] calldata _nfts) private {
        updatePool(_poolId);
        uint256 tokenId;
        uint256 amount;
        Position storage position;
        uint256 length = _nfts.length;
        uint256 totalDeposit;
        for(uint256 i; i < length;) {
            tokenId = _nfts[i].tokenId;
            position = nftPosition[_poolId][tokenId];
            if (position.stakedAmount == 0) {
                if (nftContracts[_poolId].ownerOf(tokenId) != msg.sender) revert CallerNotOwner();
            }
            amount = _nfts[i].amount;
            _depositNftGuard(_poolId, position, amount);
            totalDeposit += amount;
            emit DepositNft(msg.sender, _poolId, amount, tokenId);
            unchecked {
                ++i;
            }
        }
        if (totalDeposit > 0) braqToken.transferFrom(msg.sender, address(this), totalDeposit);
    }

    function _depositPairNft(PairNftDepositWithAmount[] calldata _nfts) private {
        uint256 length = _nfts.length;
        uint256 totalDeposit;
        PairNftDepositWithAmount memory pair;
        Position storage position;
        for(uint256 i; i < length;) {
            pair = _nfts[i];
            position = nftPosition[Pair_POOL_ID][pair.monsterTokenId];

            if(position.stakedAmount == 0) {
                if (nftContracts[BraqFriends_POOL_ID].ownerOf(pair.friendTokenId) != msg.sender
                    || FriendToMonster[pair.friendTokenId].isPaired) revert MainTokenNotOwnedOrPaired();
                if (nftContracts[Pair_POOL_ID].ownerOf(pair.monsterTokenId) != msg.sender
                    || FriendToMonster[pair.monsterTokenId].isPaired) revert MonsterNotOwnedOrPaired();

                FriendToMonster[pair.friendTokenId] = PairingStatus(pair.monsterTokenId, true);
                MonsterToFriend[pair.monsterTokenId] = PairingStatus(pair.friendTokenId, true);
            } else if (pair.friendTokenId != MonsterToFriend[pair.monsterTokenId].tokenId
                || pair.monsterTokenId != FriendToMonster[pair.friendTokenId].tokenId)
                    revert MonsterAlreadyPaired();

            _depositNftGuard(Pair_POOL_ID, position, pair.amount);
            totalDeposit += pair.amount;
            emit DepositPairNft(msg.sender, pair.amount, pair.friendTokenId, pair.monsterTokenId);
            unchecked {
                ++i;
            }
        }
        if (totalDeposit > 0) braqToken.transferFrom(msg.sender, address(this), totalDeposit);
    }

    function _depositNftGuard(uint256 _poolId, Position storage _position, uint256 _amount) private {
        if (_amount < MIN_DEPOSIT) revert DepositMoreThanOneBraq();
        if (_amount + _position.stakedAmount > pools[_poolId].timeRanges[pools[_poolId].lastRewardsRangeIndex].capPerPosition)
            revert ExceededCapAmount();

        _deposit(_poolId, _position, _amount);
    }

    function _claim(uint256 _poolId, Position storage _position, address _recipient) private returns (uint256 rewardsToBeClaimed) {
        Pool storage pool = pools[_poolId];

        int256 accumulatedBraqTokens = (_position.stakedAmount * uint256(pool.accumulatedRewardsPerShare)).toInt256();
        rewardsToBeClaimed = (accumulatedBraqTokens - _position.rewardsDebt).toUint256() / BRAQ_TOKEN_PRECISION;

        _position.rewardsDebt = accumulatedBraqTokens;

        if (rewardsToBeClaimed != 0) {
            braqToken.transfer(_recipient, rewardsToBeClaimed);
        }
    }

    function _claimNft(uint256 _poolId, uint256[] calldata _nfts, address _recipient) private {
        updatePool(_poolId);
        uint256 tokenId;
        uint256 rewardsToBeClaimed;
        uint256 length = _nfts.length;
        for(uint256 i; i < length;) {
            tokenId = _nfts[i];
            if (nftContracts[_poolId].ownerOf(tokenId) != msg.sender) revert CallerNotOwner();
            Position storage position = nftPosition[_poolId][tokenId];
            rewardsToBeClaimed = _claim(_poolId, position, _recipient);
            emit ClaimRewardsNft(msg.sender, _poolId, rewardsToBeClaimed, tokenId);
            unchecked {
                ++i;
            }
        }
    }

    function _claimPairNft(PairNft[] calldata _pairs, address _recipient) private {
        uint256 length = _pairs.length;
        uint256 friendTokenId;
        uint256 monsterTokenId;
        Position storage position;
        PairingStatus storage mainToSecond;
        PairingStatus storage secondToMain;
        for(uint256 i; i < length;) {
            friendTokenId = _pairs[i].friendTokenId;
            if (nftContracts[BraqFriends_POOL_ID].ownerOf(friendTokenId) != msg.sender) revert NotOwnerOfFriend();

            monsterTokenId = _pairs[i].monsterTokenId;
            if (nftContracts[Pair_POOL_ID].ownerOf(monsterTokenId) != msg.sender) revert NotOwnerOfMonster();

            mainToSecond = FriendToMonster[friendTokenId];
            secondToMain = MonsterToFriend[monsterTokenId];

            if (mainToSecond.tokenId != monsterTokenId || !mainToSecond.isPaired
                || secondToMain.tokenId != friendTokenId || !secondToMain.isPaired) revert ProvidedTokensNotPaired();

            position = nftPosition[Pair_POOL_ID][monsterTokenId];
            uint256 rewardsToBeClaimed = _claim(Pair_POOL_ID, position, _recipient);
            emit ClaimRewardsPairNft(msg.sender, rewardsToBeClaimed, friendTokenId, monsterTokenId);
            unchecked {
                ++i;
            }
        }
    }

    function _withdraw(uint256 _poolId, Position storage _position, uint256 _amount) private {
        if (_amount > _position.stakedAmount) revert ExceededStakedAmount();

        Pool storage pool = pools[_poolId];

        _position.stakedAmount -= _amount;
        pool.stakedAmount -= _amount.toUint96();
        _position.rewardsDebt -= (_amount * pool.accumulatedRewardsPerShare).toInt256();
    }

    function _withdrawNft(uint256 _poolId, SingleNft[] calldata _nfts, address _recipient) private {
        updatePool(_poolId);
        uint256 tokenId;
        uint256 amount;
        uint256 length = _nfts.length;
        uint256 totalWithdraw;
        Position storage position;
        for(uint256 i; i < length;) {
            tokenId = _nfts[i].tokenId;
            if (nftContracts[_poolId].ownerOf(tokenId) != msg.sender) revert CallerNotOwner();

            amount = _nfts[i].amount;
            position = nftPosition[_poolId][tokenId];
            if (amount == position.stakedAmount) {
                uint256 rewardsToBeClaimed = _claim(_poolId, position, _recipient);
                emit ClaimRewardsNft(msg.sender, _poolId, rewardsToBeClaimed, tokenId);
            }
            _withdraw(_poolId, position, amount);
            totalWithdraw += amount;
            emit WithdrawNft(msg.sender, _poolId, amount, _recipient, tokenId);
            unchecked {
                ++i;
            }
        }
        if (totalWithdraw > 0) braqToken.transfer(_recipient, totalWithdraw);
    }

    function _withdrawPairNft(PairNftWithdrawWithAmount[] calldata _nfts) private {
        address mainTokenOwner;
        address minorTokenOwner;
        PairNftWithdrawWithAmount memory pair;
        PairingStatus storage mainToSecond;
        PairingStatus storage secondToMain;
        Position storage position;
        uint256 length = _nfts.length;
        for(uint256 i; i < length;) {
            pair = _nfts[i];
            mainTokenOwner = nftContracts[BraqFriends_POOL_ID].ownerOf(pair.friendTokenId);
            minorTokenOwner = nftContracts[Pair_POOL_ID].ownerOf(pair.monsterTokenId);

            if (mainTokenOwner != msg.sender) {
                if (minorTokenOwner != msg.sender) revert NeitherTokenInPairOwnedByCaller();
            }

            mainToSecond = FriendToMonster[pair.friendTokenId];
            secondToMain = MonsterToFriend[pair.monsterTokenId];

            if (mainToSecond.tokenId != pair.monsterTokenId || !mainToSecond.isPaired
                || secondToMain.tokenId != pair.friendTokenId || !secondToMain.isPaired) revert ProvidedTokensNotPaired();

            position = nftPosition[Pair_POOL_ID][pair.monsterTokenId];
            if(!pair.isUncommit) {
                if(pair.amount == position.stakedAmount) revert UncommitWrongParameters();
            }
            if (mainTokenOwner != minorTokenOwner) {
                if (!pair.isUncommit) revert SplitPairCantPartiallyWithdraw();
            }

            if (pair.isUncommit) {
                uint256 rewardsToBeClaimed = _claim(Pair_POOL_ID, position, minorTokenOwner);
                FriendToMonster[pair.friendTokenId] = PairingStatus(0, false);
                MonsterToFriend[pair.monsterTokenId] = PairingStatus(0, false);
                emit ClaimRewardsPairNft(msg.sender, rewardsToBeClaimed, pair.friendTokenId, pair.monsterTokenId);
            }
            uint256 finalAmountToWithdraw = pair.isUncommit ? position.stakedAmount: pair.amount;
            _withdraw(Pair_POOL_ID, position, finalAmountToWithdraw);
            braqToken.transfer(mainTokenOwner, finalAmountToWithdraw);
            emit WithdrawPairNft(msg.sender, finalAmountToWithdraw, pair.friendTokenId, pair.monsterTokenId);
            unchecked {
                ++i;
            }
        }
    }

}
