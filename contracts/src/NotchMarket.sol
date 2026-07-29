// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
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
contract NotchMarket is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // --- Types ---

    /// Reviewing -> (deadline) Challengeable -> (window elapses) Final.
    /// A challenge sends it back to Reviewing for another round.
    enum Status {
        Reviewing,
        Challengeable,
        Final
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
        uint64 challengeDeadline; // set when a provisional outcome is posted
        uint8 round; // 0 for the first pass; each challenge increments
    }

    struct Review {
        uint256 yesAmount;
        uint256 noAmount;
        bool claimed;
        // Sum of (amount * consensus-at-entry, in bps) per side. Divided by the staked
        // amount this gives a stake-weighted average of how decided the market already
        // looked when this reviewer committed — which is what separates conviction from
        // joining a queue.
        uint256 entryYesWeighted;
        uint256 entryNoWeighted;
    }

    // --- Storage ---

    IERC20 public immutable collateral;
    Reputation public immutable reputation;

    /// @notice One whole unit of the collateral, i.e. 10**decimals. Read at deployment
    ///         rather than assumed, because the Rep award divides stake down to whole
    ///         tokens before taking a square root. Hard-coding 1e18 silently zeroed the
    ///         entire reputation system for any token with fewer decimals — a million
    ///         USDC would have earned nothing, with no revert to notice.
    uint256 public immutable collateralUnit;

    uint256 internal constant BPS = 10_000;

    /// @notice A zero-rep reviewer still counts at face value — diluted, never silenced.
    uint256 public constant REP_MULT_BASE_BPS = 10_000;
    /// @notice Slope on sqrt(reps). 600 puts 400 reps at 2.20x and 2,500 at 4.00x.
    uint256 public constant REP_MULT_K = 600;

    /// @notice Ceiling on the reputation multiplier, in bps. Starts at 1.5x because at
    ///         genesis nobody has Reps and a wide cap would just amplify early capital.
    ///         Widened on a published schedule as real reputation accumulates.
    uint256 public repMultCapBps = 15_000;

    /// @notice Scales the Rep award. Reps = repRate * sqrt(stake) * contest * movement,
    ///         and with three sub-1.0 factors multiplied a rate of 1 rounds ordinary
    ///         participation to zero. At 5, a solid call (1,000 staked, 0.8 contest,
    ///         0.3 movement) earns ~37, so the 4x cap is roughly 68 sustained good calls.
    ///         Tunable by owner once real distributions are observable.
    uint256 public repRate = 5;

    /// @notice How long a provisional outcome can be challenged before it finalises.
    uint64 public constant CHALLENGE_WINDOW = 48 hours;

    /// @notice Rounds of appeal allowed. Each doubles the bond, so holding a false
    ///         outcome through all of them costs roughly 8x the original margin.
    uint8 public constant MAX_ROUNDS = 3;

    /// @notice Floor on a challenge bond, so a near-tie cannot be appealed for dust.
    uint256 public minChallengeBond; // set in the constructor, scaled to the collateral

    /// @notice Delay on parameter changes that affect live markets. pause() is
    ///         deliberately exempt — an emergency stop that takes two days is not one.
    uint64 public constant ADMIN_DELAY = 48 hours;

    struct PendingCap {
        uint256 value;
        uint64 eta;
    }

    PendingCap public pendingRepMultCap;

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
    event Challenged(
        uint256 indexed artifactId, address indexed challenger, uint8 round, uint256 bond, bool backsYes
    );
    event Finalized(uint256 indexed artifactId, bool outcomeYes);
    event RepMultCapProposed(uint256 value, uint64 eta);

    constructor(address collateral_, address reputation_, address owner_) Ownable(owner_) {
        collateral = IERC20(collateral_);
        reputation = Reputation(reputation_);

        // decimals() is optional in the ERC-20 standard; fall back to 18 if absent.
        uint8 dec = 18;
        try IERC20Metadata(collateral_).decimals() returns (uint8 d) {
            dec = d;
        } catch {}
        require(dec <= 36, "collateral decimals too large");
        collateralUnit = 10 ** dec;

        // Denominate the appeal floor in whole tokens rather than wei, so the default
        // means the same thing whatever the collateral is.
        minChallengeBond = 10 * collateralUnit;
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

    /// @notice Halt new stakes. Deliberately does NOT stop resolve, finalize or claim:
    ///         pausing the exits would trap everyone's money, which is a worse failure
    ///         than whatever prompted the pause. If a payout path itself is broken, that
    ///         needs an upgrade, not a pause.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setMinChallengeBond(uint256 v) external onlyOwner {
        minChallengeBond = v;
    }

    function setRepRate(uint256 v) external onlyOwner {
        repRate = v;
    }

    /// @notice Queue a change to the multiplier ceiling. Timelocked because the cap is
    ///         read live on every vote: changing it re-weights every open market
    ///         instantly, which is not something that should land without warning.
    ///         Must stay >= 1.0x so stake is never discounted below face value.
    function proposeRepMultCapBps(uint256 v) external onlyOwner {
        require(v >= REP_MULT_BASE_BPS, "cap below base");
        pendingRepMultCap = PendingCap(v, uint64(block.timestamp) + ADMIN_DELAY);
        emit RepMultCapProposed(v, pendingRepMultCap.eta);
    }

    function executeRepMultCapBps() external onlyOwner {
        PendingCap memory p = pendingRepMultCap;
        require(p.eta != 0, "nothing pending");
        require(block.timestamp >= p.eta, "timelocked");
        repMultCapBps = p.value;
        delete pendingRepMultCap;
    }

    function cancelRepMultCapChange() external onlyOwner {
        delete pendingRepMultCap;
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

    /// @notice Share of effective weight already sitting on `support`, in bps, before the
    ///         caller's own stake lands. 50% when nothing has been staked yet — an
    ///         untouched market is maximally undecided.
    function _entryConsensusBps(Artifact storage a, bool support) internal view returns (uint256) {
        uint256 total = a.effectiveYes + a.effectiveNo;
        if (total == 0) return BPS / 2;
        uint256 side = support ? a.effectiveYes : a.effectiveNo;
        return (side * BPS) / total;
    }

    /// @notice Where consensus finished, from the winning side's point of view.
    function _finalConsensusBps(Artifact storage a) internal view returns (uint256) {
        uint256 total = a.effectiveYes + a.effectiveNo;
        if (total == 0) return BPS / 2;
        uint256 win = a.outcomeYes ? a.effectiveYes : a.effectiveNo;
        return (win * BPS) / total;
    }

    // --- Core flow ---

    /// @notice Submit a research artifact and stake on its quality.
    function submitArtifact(
        uint256 datanetId,
        string calldata title,
        string calldata contentURI,
        bytes32 contentHash,
        uint256 stakeAmount
    ) external nonReentrant whenNotPaused returns (uint256 artifactId) {
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
                effectiveNo: 0,
                challengeDeadline: 0,
                round: 0
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
    function review(uint256 artifactId, bool support, uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
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
        // Read the market before this stake moves it.
        uint256 entryBps = _entryConsensusBps(a, support);

        Review storage r = reviews[artifactId][msg.sender];
        if (support) {
            a.yesStake += amount;
            a.effectiveYes += weighted;
            r.yesAmount += amount;
            r.entryYesWeighted += amount * entryBps;
        } else {
            a.noStake += amount;
            a.effectiveNo += weighted;
            r.noAmount += amount;
            r.entryNoWeighted += amount * entryBps;
        }

        collateral.safeTransferFrom(msg.sender, address(this), amount);
        emit Reviewed(artifactId, msg.sender, support, amount);
    }

    /// @notice Resolve an artifact after its review window closes. Callable by anyone.
    ///         Outcome is the side with strictly more stake; a tie (including zero reviews)
    ///         resolves YES, so an un-reviewed submission simply returns the submitter's stake.
    function resolve(uint256 artifactId) external {
        Artifact storage a = artifacts[artifactId];
        require(a.status == Status.Reviewing, "not reviewing");
        require(block.timestamp >= a.reviewDeadline, "still reviewing");

        a.outcomeYes = a.effectiveYes >= a.effectiveNo;

        if (a.round >= MAX_ROUNDS) {
            // Appeals exhausted: this stands.
            a.status = Status.Final;
            emit Finalized(artifactId, a.outcomeYes);
        } else {
            // Provisional. Claims stay locked until the challenge window elapses.
            a.status = Status.Challengeable;
            a.challengeDeadline = uint64(block.timestamp) + CHALLENGE_WINDOW;
        }
        emit Resolved(artifactId, a.outcomeYes, a.yesStake, a.noStake);
    }

    /// @notice Bond required to challenge the current provisional outcome: 2x the margin
    ///         at round 0, then 4x, then 8x.
    ///
    ///         It must *exceed* the margin, not merely match it. A bond equal to the
    ///         margin produces a dead heat, and ties resolve YES — so the challenger
    ///         would pay in full and leave the disputed outcome standing. Doubling means
    ///         a challenge actually overturns the provisional result and puts the burden
    ///         of response back on the other side.
    function challengeBond(uint256 artifactId) public view returns (uint256) {
        Artifact storage a = artifacts[artifactId];
        uint256 margin = a.effectiveYes > a.effectiveNo
            ? a.effectiveYes - a.effectiveNo
            : a.effectiveNo - a.effectiveYes;
        uint256 b = margin << (a.round + 1);
        return b < minChallengeBond ? minChallengeBond : b;
    }

    /// @notice Dispute a provisional outcome. The bond is staked against it and review
    ///         reopens for another round, so a challenge buys scrutiny rather than a
    ///         reversal — the market still has to agree.
    function challenge(uint256 artifactId) external nonReentrant whenNotPaused {
        Artifact storage a = artifacts[artifactId];
        require(a.status == Status.Challengeable, "not challengeable");
        require(block.timestamp < a.challengeDeadline, "challenge window closed");
        require(a.round < MAX_ROUNDS, "no rounds left");
        // Same rule as review(): an author cannot buy validation of their own work,
        // and their submit stake already sits on the YES side.
        require(msg.sender != a.submitter, "submitter cannot challenge");

        uint256 bond = challengeBond(artifactId);
        bool backsYes = !a.outcomeYes; // you only challenge what you disagree with

        uint256 weighted = (bond * repMultiplierBps(reputation.repOf(msg.sender))) / BPS;
        uint256 entryBps = _entryConsensusBps(a, backsYes);
        Review storage r = reviews[artifactId][msg.sender];
        if (backsYes) {
            a.yesStake += bond;
            a.effectiveYes += weighted;
            r.yesAmount += bond;
            r.entryYesWeighted += bond * entryBps;
        } else {
            a.noStake += bond;
            a.effectiveNo += weighted;
            r.noAmount += bond;
            r.entryNoWeighted += bond * entryBps;
        }

        a.round += 1;
        a.status = Status.Reviewing;
        a.reviewDeadline = uint64(block.timestamp) + datanets[a.datanetId].reviewWindow;
        a.challengeDeadline = 0;

        collateral.safeTransferFrom(msg.sender, address(this), bond);
        emit Challenged(artifactId, msg.sender, a.round, bond, backsYes);
    }

    /// @notice Lock in a provisional outcome once its challenge window has passed.
    ///         Permissionless — anyone can pay the gas to unlock claims.
    function finalize(uint256 artifactId) external {
        Artifact storage a = artifacts[artifactId];
        require(a.status == Status.Challengeable, "not challengeable");
        require(block.timestamp >= a.challengeDeadline, "challenge window open");
        a.status = Status.Final;
        emit Finalized(artifactId, a.outcomeYes);
    }

    /// @notice Claim winnings and Reps for an artifact. Winners get their stake back plus a
    ///         pro-rata share of the losing pool; losers get nothing. The submitter claims via
    ///         the same function (their submit stake counts as YES-side weight).
    function claim(uint256 artifactId) external nonReentrant {
        Artifact storage a = artifacts[artifactId];
        require(a.status == Status.Final, "not final");

        uint256 payout;
        uint256 reps;

        (uint256 winWeight, uint256 losePool) = a.outcomeYes
            ? (a.submitStake + a.yesStake, a.noStake)
            : (a.noStake, a.yesStake + a.submitStake);

        // Weight this caller contributes to the winning side (0 if they lost), plus
        // sum(stake * entry-consensus) so we can recover where they came in.
        uint256 myWeight;
        uint256 entryAcc;

        if (msg.sender == a.submitter && !a.submitterClaimed) {
            a.submitterClaimed = true;
            if (a.outcomeYes) {
                myWeight += a.submitStake; // else: slashed, closes their record
                // The author committed before any review existed — maximally undecided.
                entryAcc += a.submitStake * (BPS / 2);
            }
        }

        Review storage r = reviews[artifactId][msg.sender];
        if (!r.claimed && (r.yesAmount > 0 || r.noAmount > 0)) {
            r.claimed = true;
            myWeight += a.outcomeYes ? r.yesAmount : r.noAmount;
            entryAcc += a.outcomeYes ? r.entryYesWeighted : r.entryNoWeighted;
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

            // Reps = sqrt(stake) * contest * movement.
            //
            //   sqrt(stake)  100x the capital earns 10x the reputation, not 100x.
            //   contest      zero when a side went unopposed, so nothing is minted from
            //                a market nobody argued with.
            //   movement     how far consensus travelled toward you *after* you staked.
            //
            // Movement is what separates conviction from conformity. Backing a side at
            // 20% and watching it close at 70% is a call. Joining at 90% is a queue.
            // Both are "on the winning side"; only one is evidence of judgment. Without
            // this the cheapest way to farm reputation is to wait until a market is
            // nearly settled and pile onto the leader.
            uint256 cf = contestFactorBps(a.effectiveYes, a.effectiveNo);
            if (cf > 0) {
                uint256 avgEntryBps = entryAcc / myWeight;
                uint256 finalBps = _finalConsensusBps(a);
                uint256 movementBps = finalBps > avgEntryBps ? finalBps - avgEntryBps : 0;
                if (movementBps > 0) {
                    reps =
                        (repRate * Math.sqrt(myWeight / collateralUnit) * cf * movementBps) / (BPS * BPS);
                }
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
