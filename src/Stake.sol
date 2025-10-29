// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title StakingNFT - stake represented as ERC721 position NFTs
/// @author atharva
/// @notice Each stake mints an NFT. Only the current NFT owner can claim ROI or unstake
/// @dev Uses SafeERC20 for token transfers. Referal (0.5%) paid imediately from deposited amount.
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract StakingNFT is ERC721, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAmount();
    error InvalidReferrer();
    error NotStakeOwner();
    error NoRewardsAvailable();
    error InsufficientContractBalance();
    error StakeDoesNotExist();
    error CannotUnstakeZero();
    error InvalidParameter();
    error ClaimIntervalNotMet();
    error InvalidBeneficiary();
    error DailyROITooHigh();
    error ReferralRateTooHigh();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event StakeCreated(
        address indexed staker, address referrer, uint256 indexed amount, uint256 indexed stakeId, uint40 timestamp
    );
    event ReferralPaid(address indexed referrer, uint256 indexed stakeId, uint256 amount);
    event Claimed(address indexed claimer, uint256 indexed stakeId, uint256 indexed reward, uint256 timestamp);
    event Unstaked(
        address indexed owner, uint256 indexed stakeId, uint256 principal, uint256 reward, address beneficiary
    );
    event EmergencyRecovered(address indexed token, address indexed to, uint256 amount);
    event ContractFunded(uint256 amount);
    event DailyROIUpdated(uint256 newDailyROI);
    event ReferralRateUpdated(uint256 newReferralRate);
    event ClaimIntervalUpdated(uint256 newInterval);
    event EmergencyWithdraw(address indexed owner, uint256 indexed stakeId, uint256 principal, address beneficiary);

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct Stake {
        address staker; // orignal staker (for info)
        address referrer; // referer (if any) else address 0
        uint256 amount_staked; // principle (after referral deduction - if any)
        uint256 stakeId; // equals tokenId of the ERC721 - only owner of this token id has right to claim or unstake
        uint40 last_claim_timestamp; // last time rewards claimed on this position
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTANTS / STATE
    //////////////////////////////////////////////////////////////*/
    // daily roi denominator
    uint256 public constant DEN = 10_000;

    // Maximum daily ROI: 5% (500/10000)
    uint256 public constant MAX_DAILY_ROI = 500;

    // Maximum referal rate: 10% (1000/10000)
    uint256 public constant MAX_REFERRAL_RATE = 1000;

    // daily roi numerator - 1 % of 10_000 = 100
    uint256 public DAILY = 100;

    // referral reward - 0.5 % of 10_000 = 50
    uint256 public REFERRAL = 50;

    // minimun interval between two claims - 24 hours
    uint40 public CLAIM_INTERVAL = uint40(24 hours);

    // token being staked
    IERC20 public immutable stakingToken;

    // Whether the staking token suports permit
    bool public immutable supportsPermit;

    // nextStakeId holder
    uint256 public nextStakeId = 1;

    // total principle currently staked in contract
    uint256 public totalStaked;

    // mapping from stake id to the data struct of that stakeId
    mapping(uint256 => Stake) public stakeIdToStakeData;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    // make sure the claimer / unstaker is either the owner of the stake or approved for it
    modifier onlyStakeOwnerOrApproved(uint256 stakeId) {
        if (
            ownerOf(stakeId) != msg.sender && msg.sender != getApproved(stakeId)
                && !isApprovedForAll(ownerOf(stakeId), msg.sender)
        ) revert NotStakeOwner();
        _;
    }

    modifier stakeExists(uint256 stakeId) {
        if (ownerOf(stakeId) == address(0)) revert StakeDoesNotExist();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @param _name name of nft
    /// @param _symbol symbol of nft
    /// @param _stakingToken address of underlying BEP-20 token being staked
    constructor(string memory _name, string memory _symbol, address _stakingToken)
        ERC721(_name, _symbol)
        Ownable(msg.sender)
    {
        require(_stakingToken != address(0), "zero token addr");
        stakingToken = IERC20(_stakingToken);

        bool _supportsPermit;
        // Check if token supports permit
        try IERC20Permit(_stakingToken).DOMAIN_SEPARATOR() returns (bytes32) {
            _supportsPermit = true;
        } catch {
            _supportsPermit = false;
        }
        supportsPermit = _supportsPermit;
    }

    /*//////////////////////////////////////////////////////////////
                             USER-FACING ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new stake; mints an NFT (tokenId == stakeId) to `beneficiary` (msg.sender by default)
    /// @param amount Exact amount the user wants to stake (full amount must be aproved to this contract)
    /// @param referrer Optional referer address (use address(0) to skip)
    /// @return stakeId newly minted stake (tokenId)
    function stake(uint256 amount, address referrer) external whenNotPaused nonReentrant returns (uint256 stakeId) {
        if (amount == 0) revert ZeroAmount();
        if (referrer == msg.sender) revert InvalidReferrer();

        return _createStake(msg.sender, referrer, amount);
    }

    /// @notice Create a stake using EIP-2612 permit (gasless approval + stake in one transaction)
    /// @param amount Amount to stake
    /// @param referrer Optional referer address
    /// @param deadline Permit deadline
    /// @param v ECDSA signature component
    /// @param r ECDSA signature component
    /// @param s ECDSA signature component
    /// @return stakeId newly minted stake (tokenId)
    function stakeWithPermit(uint256 amount, address referrer, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 stakeId)
    {
        if (amount == 0) revert ZeroAmount();
        if (referrer == msg.sender) revert InvalidReferrer();
        if (!supportsPermit) revert InvalidParameter();

        // Execute permit
        IERC20Permit(address(stakingToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);

        return _createStake(msg.sender, referrer, amount);
    }

    /// @notice Claim daily ROI rewards for a given stake NFT
    /// @param stakeId The tokenId of the stake (also stakeId)
    function claim(uint256 stakeId, address beneficiary)
        external
        nonReentrant
        whenNotPaused
        onlyStakeOwnerOrApproved(stakeId)
        stakeExists(stakeId)
    {
        if (beneficiary == address(0)) revert InvalidBeneficiary();

        Stake storage userStake = stakeIdToStakeData[stakeId];
        uint40 lastClaim = userStake.last_claim_timestamp;

        // Check if claim interval has passed
        if (block.timestamp < lastClaim + CLAIM_INTERVAL) revert ClaimIntervalNotMet();

        // calculate full days passed
        uint256 daysPassed = (block.timestamp - lastClaim) / 1 days;
        if (daysPassed == 0) revert NoRewardsAvailable();

        // calculate reward = principal * DAILY% * daysPassed
        // Add overflow protection for very old stakes
        uint256 principal = userStake.amount_staked;
        uint256 reward;
        unchecked {
            // Safe from overflow if daysPassed < ~10^59 days for reasonable stake amounts
            uint256 temp = principal * DAILY;
            if (temp / principal != DAILY) revert InvalidParameter(); // overflow check
            reward = (temp * daysPassed) / DEN;
        }

        // sanity check: contract must have enough tokens to pay reward and still have enough tokens to return all the stakes
        uint256 bal = stakingToken.balanceOf(address(this));
        if (bal < totalStaked + reward) revert InsufficientContractBalance();

        // update state - update storage variable directly
        userStake.last_claim_timestamp = lastClaim + uint40(daysPassed * 1 days);

        // transfer reward
        stakingToken.safeTransfer(beneficiary, reward);

        emit Claimed(msg.sender, stakeId, reward, block.timestamp);
    }

    /// @notice Unstake principal and any pending rewards for given stake NFT
    /// @param stakeId The NFT tokenId representing the stake position
    /// @param beneficiary The address that will recieve the unstaked principal + rewards
    function unstake(uint256 stakeId, address beneficiary)
        external
        nonReentrant
        whenNotPaused
        onlyStakeOwnerOrApproved(stakeId)
        stakeExists(stakeId)
    {
        if (beneficiary == address(0)) revert InvalidBeneficiary();

        Stake memory userStake = stakeIdToStakeData[stakeId];
        uint40 lastClaim = userStake.last_claim_timestamp;
        uint256 principal = userStake.amount_staked;

        if (principal == 0) revert CannotUnstakeZero();

        // calculate any pending rewards
        uint256 daysPassed = (block.timestamp - lastClaim) / 1 days;
        uint256 reward;
        unchecked {
            uint256 temp = principal * DAILY;
            if (temp / principal != DAILY) revert InvalidParameter();
            reward = (temp * daysPassed) / DEN;
        }

        // check contract liquidity (must cover all staked + reward)
        uint256 bal = stakingToken.balanceOf(address(this));
        if (bal < totalStaked + reward) revert InsufficientContractBalance();

        // update global + local state
        totalStaked -= principal;
        delete stakeIdToStakeData[stakeId]; // delete struct from storage
        _burn(stakeId); // burn NFT so ownership of stake is gone

        // transfer principal + rewards
        stakingToken.safeTransfer(beneficiary, principal + reward);

        emit Unstaked(msg.sender, stakeId, principal, reward, beneficiary);
    }

    /// @notice Emergency withdraw principal only (no rewards) - works even when paused
    /// @param stakeId The NFT tokenId representing stake position
    /// @param beneficiary The address that will recieve the principal
    function emergencyWithdraw(uint256 stakeId, address beneficiary)
        external
        nonReentrant
        onlyStakeOwnerOrApproved(stakeId)
        stakeExists(stakeId)
    {
        if (beneficiary == address(0)) revert InvalidBeneficiary();

        Stake memory userStake = stakeIdToStakeData[stakeId];
        uint256 principal = userStake.amount_staked;

        if (principal == 0) revert CannotUnstakeZero();

        // check contract has enough to return principal
        uint256 bal = stakingToken.balanceOf(address(this));
        if (bal < principal) revert InsufficientContractBalance();

        // update global + local state
        totalStaked -= principal;
        delete stakeIdToStakeData[stakeId];
        _burn(stakeId);

        // transfer only principal (no rewards in emergency)
        stakingToken.safeTransfer(beneficiary, principal);

        emit EmergencyWithdraw(msg.sender, stakeId, principal, beneficiary);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createStake(address staker, address referrer, uint256 amount) internal returns (uint256) {
        uint256 stakeId = nextStakeId;
        uint256 referrerReward;
        uint256 netStake;

        if (referrer == address(0)) {
            netStake = amount;
        } else {
            referrerReward = (amount * REFERRAL) / DEN;
            netStake = amount - referrerReward;
        }

        Stake memory newStake = Stake({
            staker: staker,
            referrer: referrer,
            amount_staked: netStake,
            stakeId: stakeId,
            last_claim_timestamp: uint40(block.timestamp)
        });

        // Transfer staking tokens to contract (using SafeERC20 consistently)
        stakingToken.safeTransferFrom(staker, address(this), amount);

        stakeIdToStakeData[stakeId] = newStake;
        totalStaked += netStake;
        nextStakeId += 1;

        _mint(staker, stakeId);

        // Pay referrer if applicable
        if (referrer != address(0)) {
            stakingToken.safeTransfer(referrer, referrerReward);
            emit ReferralPaid(referrer, stakeId, referrerReward);
        }

        emit StakeCreated(staker, referrer, netStake, stakeId, uint40(block.timestamp));

        return stakeId;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setDailyROI(uint256 newDailyROI) external onlyOwner {
        if (newDailyROI > MAX_DAILY_ROI) revert DailyROITooHigh();
        DAILY = newDailyROI;
        emit DailyROIUpdated(newDailyROI);
    }

    function setReferralRate(uint256 newReferralRate) external onlyOwner {
        if (newReferralRate > MAX_REFERRAL_RATE) revert ReferralRateTooHigh();
        REFERRAL = newReferralRate;
        emit ReferralRateUpdated(newReferralRate);
    }

    function setClaimInterval(uint40 newInterval) external onlyOwner {
        if (newInterval == 0) revert InvalidParameter();
        CLAIM_INTERVAL = newInterval;
        emit ClaimIntervalUpdated(newInterval);
    }

    function fundContract(uint256 amount) external onlyOwner {
        if (amount == 0) revert InvalidParameter();
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit ContractFunded(amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Emergency recovery of tokens (should only be used for accidentally sent tokens, not staked tokens)
    function emergencyRecoverTokens(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(stakingToken)) {
            // Prevent owner from withdrawing staked funds
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (bal < totalStaked + amount) revert InsufficientContractBalance();
        }
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyRecovered(token, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice returns the daily ROI rate for exmaple 100 = 1% if DEN = 10000
    function getRewardRate() external view returns (uint256) {
        return DAILY;
    }

    /// @notice returns the referral reward rate for exampl 50 = 0.5% if DEN = 10000
    function getReferralRate() external view returns (uint256) {
        return REFERRAL;
    }

    /// @notice returns the current claim interval example 1 days = 86400 seconds
    function getClaimInterval() external view returns (uint256) {
        return CLAIM_INTERVAL;
    }

    /// @notice returns the pending rewards for a given stakeId
    function getPendingRewards(uint256 stakeId) external view returns (uint256 pendingReward) {
        Stake memory userStake = stakeIdToStakeData[stakeId];
        if (userStake.staker == address(0)) return 0; // stake doesn't exist

        uint256 daysPassed = (block.timestamp - userStake.last_claim_timestamp) / 1 days;
        if (daysPassed == 0) return 0;

        pendingReward = (userStake.amount_staked * DAILY * daysPassed) / DEN;
    }

    /// @notice returns the full Stake struct data for a given stakeId
    function getStakeData(uint256 stakeId) external view returns (Stake memory) {
        return stakeIdToStakeData[stakeId];
    }

    /// @notice returns whether token supports permit functionality
    function tokenSupportsPermit() external view returns (bool) {
        return supportsPermit;
    }
}
