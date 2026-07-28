// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Reputation} from "./Reputation.sol";

/// @title NotchMarket
/// @notice A research-quality staking market ("true Reppo"). Researchers submit an analysis
///         artifact and stake collateral on it being high-signal. Reviewers stake YES (meets
///         the quality bar) or NO (does not). After the review window, the market resolves to
///         whichever side holds more stake; the losing pool is redistributed pro-rata to the
///         winners, and winners earn non-transferable Reputation.
///
///         The submitter is treated as a YES-side participant: they win with YES reviewers and
///         are slashed with them if NO prevails. Every payout is funded entirely by staked
///         collateral — the contract never mints or owes money it does not hold.
contract NotchMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Types ---

    enum Status {
        Reviewing,
        Resolved
    }

    struct Datanet {
        string name;
        string description;
        uint256 minSubmitStake; // minimum collateral a submitter must post
        uint64 reviewWindow; // seconds reviewers have to stake after a submission
        uint256 minReviewerRep; // Reps required to review here (0 = open to all)
        bool exists;
    }

    struct Artifact {
        uint256 datanetId;
        address submitter;
        string title;
        string contentURI; // ipfs://… or https://… pointer to the full analysis
        // keccak256 of the analysis as it read at submission. The chain cannot fetch a
        // URL, so this is the submitter's commitment: readers re-fetch, re-hash, and
        // compare. A mismatch proves the content changed after stakes were placed.
        // bytes32(0) means the submitter declined to commit — treat as unverifiable.
        bytes32 contentHash;
        uint256 submitStake;
        uint64 reviewDeadline;
        uint256 yesStake; // total reviewer stake on YES
        uint256 noStake; // total reviewer stake on NO
        Status status;
        bool outcomeYes; // valid once Resolved
        bool submitterClaimed;
        // Progress of the payout sweep. Appended at the end so the struct's existing
        // field order (and the getArtifact tuple) stays stable for readers.
        uint256 claimedWinWeight; // winning-side weight that has already claimed
        uint256 distributedLosePool; // losing pool paid out so far
    }

    struct Review {
        uint256 yesAmount;
        uint256 noAmount;
        bool claimed;
    }

    // --- Storage ---

    IERC20 public immutable collateral;
    Reputation public immutable reputation;

    /// @notice Reps minted per 1e18 of winning stake. Tunable by owner.
    uint256 public repPerToken = 1;

    Datanet[] public datanets;
    Artifact[] public artifacts;

    /// @dev artifactId => reviewer => stake record
    mapping(uint256 => mapping(address => Review)) public reviews;

    // --- Events ---

    event DatanetCreated(
        uint256 indexed datanetId, string name, uint256 minSubmitStake, uint64 reviewWindow
    );
    event ArtifactSubmitted(
        uint256 indexed artifactId,
        uint256 indexed datanetId,
        address indexed submitter,
        string title,
        string contentURI,
        bytes32 contentHash,
        uint256 submitStake,
        uint64 reviewDeadline
    );
    event Reviewed(
        uint256 indexed artifactId, address indexed reviewer, bool support, uint256 amount
    );
    event Resolved(uint256 indexed artifactId, bool outcomeYes, uint256 yesStake, uint256 noStake);
    event Claimed(uint256 indexed artifactId, address indexed account, uint256 payout, uint256 reps);

    constructor(address collateral_, address reputation_, address owner_) Ownable(owner_) {
        collateral = IERC20(collateral_);
        reputation = Reputation(reputation_);
    }

    // --- Admin ---

    function createDatanet(
        string calldata name,
        string calldata description,
        uint256 minSubmitStake,
        uint64 reviewWindow,
        uint256 minReviewerRep
    ) external onlyOwner returns (uint256 datanetId) {
        require(reviewWindow > 0, "window=0");
        datanetId = datanets.length;
        datanets.push(
            Datanet({
                name: name,
                description: description,
                minSubmitStake: minSubmitStake,
                reviewWindow: reviewWindow,
                minReviewerRep: minReviewerRep,
                exists: true
            })
        );
        emit DatanetCreated(datanetId, name, minSubmitStake, reviewWindow);
    }

    function setRepPerToken(uint256 v) external onlyOwner {
        repPerToken = v;
    }

    // --- Core flow ---

    /// @notice Submit a research artifact and stake on its quality.
    function submitArtifact(
        uint256 datanetId,
        string calldata title,
        string calldata contentURI,
        bytes32 contentHash,
        uint256 stakeAmount
    ) external nonReentrant returns (uint256 artifactId) {
        Datanet storage d = datanets[datanetId];
        require(d.exists, "no datanet");
        require(stakeAmount >= d.minSubmitStake, "stake too low");
        require(bytes(title).length > 0, "empty title");

        uint64 deadline = uint64(block.timestamp) + d.reviewWindow;
        artifactId = artifacts.length;
        artifacts.push(
            Artifact({
                datanetId: datanetId,
                submitter: msg.sender,
                title: title,
                contentURI: contentURI,
                contentHash: contentHash,
                submitStake: stakeAmount,
                reviewDeadline: deadline,
                yesStake: 0,
                noStake: 0,
                status: Status.Reviewing,
                outcomeYes: false,
                submitterClaimed: false,
                claimedWinWeight: 0,
                distributedLosePool: 0
            })
        );

        collateral.safeTransferFrom(msg.sender, address(this), stakeAmount);
        emit ArtifactSubmitted(
            artifactId,
            datanetId,
            msg.sender,
            title,
            contentURI,
            contentHash,
            stakeAmount,
            deadline
        );
    }

    /// @notice Stake YES (high quality) or NO (low quality) on an artifact.
    function review(uint256 artifactId, bool support, uint256 amount) external nonReentrant {
        Artifact storage a = artifacts[artifactId];
        require(a.status == Status.Reviewing, "not reviewing");
        require(block.timestamp < a.reviewDeadline, "review closed");
        require(msg.sender != a.submitter, "submitter cannot review");
        require(amount > 0, "amount=0");

        Datanet storage d = datanets[a.datanetId];
        if (d.minReviewerRep > 0) {
            require(reputation.repOf(msg.sender) >= d.minReviewerRep, "insufficient rep");
        }

        Review storage r = reviews[artifactId][msg.sender];
        if (support) {
            a.yesStake += amount;
            r.yesAmount += amount;
        } else {
            a.noStake += amount;
            r.noAmount += amount;
        }

        collateral.safeTransferFrom(msg.sender, address(this), amount);
        emit Reviewed(artifactId, msg.sender, support, amount);
    }

    /// @notice Resolve an artifact after its review window closes. Callable by anyone.
    ///         Outcome is the side with strictly more stake; a tie (including zero reviews)
    ///         resolves YES, so an un-reviewed submission simply returns the submitter's stake.
    function resolve(uint256 artifactId) external {
        Artifact storage a = artifacts[artifactId];
        require(a.status == Status.Reviewing, "already resolved");
        require(block.timestamp >= a.reviewDeadline, "still reviewing");

        a.outcomeYes = a.yesStake >= a.noStake;
        a.status = Status.Resolved;
        emit Resolved(artifactId, a.outcomeYes, a.yesStake, a.noStake);
    }

    /// @notice Claim winnings and Reps for an artifact. Winners get their stake back plus a
    ///         pro-rata share of the losing pool; losers get nothing. The submitter claims via
    ///         the same function (their submit stake counts as YES-side weight).
    function claim(uint256 artifactId) external nonReentrant {
        Artifact storage a = artifacts[artifactId];
        require(a.status == Status.Resolved, "not resolved");

        uint256 payout;
        uint256 reps;

        (uint256 winWeight, uint256 losePool) = a.outcomeYes
            ? (a.submitStake + a.yesStake, a.noStake)
            : (a.noStake, a.yesStake + a.submitStake);

        // Weight this caller contributes to the winning side (0 if they lost).
        uint256 myWeight;

        if (msg.sender == a.submitter && !a.submitterClaimed) {
            a.submitterClaimed = true;
            if (a.outcomeYes) myWeight += a.submitStake; // else: slashed, closes their record
        }

        Review storage r = reviews[artifactId][msg.sender];
        if (!r.claimed && (r.yesAmount > 0 || r.noAmount > 0)) {
            r.claimed = true;
            myWeight += a.outcomeYes ? r.yesAmount : r.noAmount;
        }

        if (myWeight > 0) {
            uint256 share = winWeight == 0 ? 0 : (losePool * myWeight) / winWeight;
            a.claimedWinWeight += myWeight;
            a.distributedLosePool += share;

            // Integer division truncates, so the shares can sum to less than losePool.
            // The final winner to claim sweeps whatever is left, which keeps the escrow
            // draining to exactly zero instead of stranding dust forever.
            if (a.claimedWinWeight == winWeight) {
                share += losePool - a.distributedLosePool;
                a.distributedLosePool = losePool;
            }

            payout = myWeight + share;
            reps = (myWeight * repPerToken) / 1 ether;
        }

        require(payout > 0 || reps > 0, "nothing to claim");
        if (reps > 0) reputation.award(msg.sender, reps);
        if (payout > 0) collateral.safeTransfer(msg.sender, payout);
        emit Claimed(artifactId, msg.sender, payout, reps);
    }

    // --- Views ---

    function datanetCount() external view returns (uint256) {
        return datanets.length;
    }

    function artifactCount() external view returns (uint256) {
        return artifacts.length;
    }

    function getArtifact(uint256 artifactId) external view returns (Artifact memory) {
        return artifacts[artifactId];
    }

    function getReview(uint256 artifactId, address account)
        external
        view
        returns (Review memory)
    {
        return reviews[artifactId][account];
    }

    /// @notice Current YES share in basis points (0–10000). Returns 5000 with no reviews.
    function consensusBps(uint256 artifactId) external view returns (uint256) {
        Artifact storage a = artifacts[artifactId];
        uint256 total = a.yesStake + a.noStake;
        if (total == 0) return 5000;
        return (a.yesStake * 10_000) / total;
    }
}
