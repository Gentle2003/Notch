// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
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
        // Reputation-weighted stake per side. These decide the outcome; the raw
        // yesStake/noStake above still decide the payouts.
        uint256 effectiveYes;
        uint256 effectiveNo;
    }

    struct Review {
        uint256 yesAmount;
        uint256 noAmount;
        bool claimed;
    }

    // --- Storage ---

    IERC20 public immutable collateral;
    Reputation public immutable reputation;

    uint256 internal constant BPS = 10_000;

    /// @notice A zero-rep reviewer still counts at face value — diluted, never silenced.
    uint256 public constant REP_MULT_BASE_BPS = 10_000;
    /// @notice Slope on sqrt(reps). 600 puts 400 reps at 2.20x and 2,500 at 4.00x.
    uint256 public constant REP_MULT_K = 600;

    /// @notice Ceiling on the reputation multiplier, in bps. Starts at 1.5x because at
    ///         genesis nobody has Reps and a wide cap would just amplify early capital.
    ///         Widened on a published schedule as real reputation accumulates.
    uint256 public repMultCapBps = 15_000;

    /// @notice Reps minted per sqrt(whole token) of winning stake, before the contest
    ///         factor. Tunable by owner.
    uint256 public repRate = 1;

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

    function setRepRate(uint256 v) external onlyOwner {
        repRate = v;
    }

    /// @notice Widen (or narrow) the reputation multiplier ceiling. Must stay >= 1.0x so
    ///         stake is never discounted below face value.
    function setRepMultCapBps(uint256 v) external onlyOwner {
        require(v >= REP_MULT_BASE_BPS, "cap below base");
        repMultCapBps = v;
    }

    // --- Weighting ---

    /// @notice How much each token of stake counts, given the staker's reputation.
    ///         min(cap, 1.00x + 0.06 * sqrt(reps)). Square root so influence keeps
    ///         growing with a track record but with diminishing returns — no reviewer
    ///         becomes a dictator.
    function repMultiplierBps(uint256 reps) public view returns (uint256) {
        uint256 v = REP_MULT_BASE_BPS + REP_MULT_K * Math.sqrt(reps);
        uint256 cap = repMultCapBps;
        return v < cap ? v : cap;
    }

    /// @notice How genuinely contested an artifact was, 0 … 10_000.
    ///         2 * min(side) / total: 1.0 when perfectly split, 0 when one side is
    ///         unopposed. Reps are scaled by this, so being right when nobody disagreed
    ///         earns nothing — which is what stops reputation being farmed for free.
    function contestFactorBps(uint256 wYes, uint256 wNo) public pure returns (uint256) {
        uint256 total = wYes + wNo;
        if (total == 0) return 0;
        uint256 lo = wYes < wNo ? wYes : wNo;
        return (2 * BPS * lo) / total;
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
                distributedLosePool: 0,
                effectiveYes: 0,
                effectiveNo: 0
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

        // Snapshot reputation now, so Reps earned elsewhere mid-window cannot
        // retroactively strengthen a position already taken.
        uint256 weighted = (amount * repMultiplierBps(reputation.repOf(msg.sender))) / BPS;

        Review storage r = reviews[artifactId][msg.sender];
        if (support) {
            a.yesStake += amount;
            a.effectiveYes += weighted;
            r.yesAmount += amount;
        } else {
            a.noStake += amount;
            a.effectiveNo += weighted;
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

        a.outcomeYes = a.effectiveYes >= a.effectiveNo;
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

            // Reps scale with sqrt(stake), not stake, so 100x the capital earns 10x the
            // reputation rather than 100x. Multiplied by how contested the artifact was,
            // which is zero when one side went unopposed.
            uint256 cf = contestFactorBps(a.effectiveYes, a.effectiveNo);
            if (cf > 0) {
                reps = (repRate * Math.sqrt(myWeight / 1 ether) * cf) / BPS;
            }
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
