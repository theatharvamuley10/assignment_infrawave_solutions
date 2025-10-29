// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title StakingNFT - stake represented as ERC721 position NFTs
/// @author ...
/// @notice Each stake mints an NFT. Only the current NFT owner can claim ROI or unstake.
/// @dev Uses SafeERC20 for token transfers. Referral (0.5%) paid immediately from deposited amount.
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    event FundedContract(uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct Stake {
        address staker; // original staker (for info)
        address referrer; // referrer (if any) else address 0
        uint256 amount_staked; // principal (after referral deduction - if any)
        uint256 stakeId; // equals tokenId of the ERC721 - only owner of this token id has the right to claim or unstake
        uint40 last_claim_timestamp; // last time rewards were claimed on this particular position
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTANTS / STATE
    //////////////////////////////////////////////////////////////*/
    // daily roi denominator
    uint256 public constant DEN = 10_000;

    // daily roi numerator - 1 % of 10_000 = 100
    uint256 public DAILY = 100;

    // referral reward - 0.5 % of 10_000 = 50
    uint256 public REFERRAL = 50;

    // minimum interval between two claims - 24 hours
    uint40 public CLAIM_INTERVAL = uint40(24 hours);

    // token being staked
    IERC20 public immutable stakingToken;

    // nextStakeId holder
    uint256 public nextStakeId = 1;

    // total principle currently staked in the contract
    uint256 public totalStaked;

    // mapping from stake id to the data struct of that stakeId
    mapping(uint256 => Stake) public stakeIdToStakeData;

    // convenient mapping for displaying all staking positions owned by a particular address
    // mapping(address => uint256[]) private _ownerToStakeIds;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyStakeOwner(uint256 stakeId) {
        if (ownerOf(stakeId) != msg.sender) revert NotStakeOwner();
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
    }

    /*//////////////////////////////////////////////////////////////
                             USER-FACING ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new stake; mints an NFT (tokenId == stakeId) to `beneficiary` (msg.sender by default).
    /// @param amount Exact amount the user wants to stake (full amount must be approved to this contract)
    /// @param referrer Optional referrer address (use address(0) to skip)
    /// @return stakeId newly minted stake (tokenId)
    function stake(uint256 amount, address referrer) external whenNotPaused nonReentrant returns (uint256 stakeId) {
        if (amount == 0) revert ZeroAmount();
        if (referrer == msg.sender) revert InvalidReferrer();

        if (referrer == address(0)) {
            return _createStakeWithoutReferrer(msg.sender, referrer, amount, nextStakeId, uint40(block.timestamp));
        } else {
            return _createStakeWithReferrer(msg.sender, referrer, amount, nextStakeId, uint40(block.timestamp));
        }
    }

    function _createStakeWithoutReferrer(
        address staker,
        address referrer,
        uint256 amountStaked,
        uint256 stakeId,
        uint40 timestamp
    ) internal returns (uint256) {
        Stake memory newStake = Stake({
            staker: staker,
            referrer: referrer,
            amount_staked: amountStaked,
            stakeId: stakeId,
            last_claim_timestamp: timestamp
        });

        // Transfer staking tokens to contract
        stakingToken.safeTransferFrom(staker, address(this), amountStaked);

        stakeIdToStakeData[stakeId] = newStake;
        totalStaked += amountStaked;
        nextStakeId += 1;

        _mint(staker, stakeId);

        emit StakeCreated(
            newStake.staker, newStake.referrer, newStake.amount_staked, newStake.stakeId, newStake.last_claim_timestamp
        );

        return newStake.stakeId;
    }

    function _createStakeWithReferrer(
        address staker,
        address referrer,
        uint256 amountStaked,
        uint256 stakeId,
        uint40 timestamp
    ) internal returns (uint256) {
        uint256 referrerReward = (amountStaked * REFERRAL) / DEN;
        uint256 netStake = amountStaked - referrerReward;

        // transfer full amount to contract
        stakingToken.transferFrom(staker, address(this), amountStaked);

        Stake memory newStake = Stake({
            staker: staker,
            referrer: referrer,
            amount_staked: netStake,
            stakeId: stakeId,
            last_claim_timestamp: timestamp
        });

        stakeIdToStakeData[stakeId] = newStake;
        totalStaked += netStake;
        nextStakeId += 1;

        _mint(staker, stakeId);
        // reward referrer
        stakingToken.safeTransferFrom(address(this), referrer, referrerReward);

        emit StakeCreated(
            newStake.staker, newStake.referrer, newStake.amount_staked, newStake.stakeId, newStake.last_claim_timestamp
        );

        return newStake.stakeId;
    }
}
