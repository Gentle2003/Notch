// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Reputation
/// @notice Non-transferable reputation ("Reps") earned by correctly staking on contested
///         research. Only authorised markets may award Reps. Reps gate access to
///         higher-trust datanets and weight a reviewer's vote.
///
///         Reps are deliberately soulbound: there are no transfer or approve functions, so
///         reputation cannot be bought, sold, or delegated — it must be earned.
///
///         Reps are never confiscated. Being wrong costs capital, not history. What does
///         change is *weight*: the value returned by `repOf` halves every `HALF_LIFE` of
///         inactivity, so influence reflects recent judgment and has to be maintained.
///         `lifetimeRep` keeps the undecayed total as a permanent record.
contract Reputation is Ownable {
    /// @notice Reps ever earned, never reduced. The historical record.
    mapping(address => uint256) public lifetimeRep;

    /// @notice When this account last earned Reps. Decay is measured from here.
    mapping(address => uint64) public lastAwardAt;

    /// @notice Markets allowed to mint Reps.
    mapping(address => bool) public isMarket;

    /// @notice Cumulative Reps ever minted (a global leaderboard denominator).
    uint256 public totalRep;

    /// @notice Weight halves for every half-life elapsed since the last award.
    uint64 public constant HALF_LIFE = 180 days;

    event MarketSet(address indexed market, bool allowed);
    event RepAwarded(address indexed account, uint256 amount, uint256 newLifetime);

    /// @notice Delay before a change to minting authority takes effect. Authorising a
    ///         contract to mint Reps is the most dangerous power here — reputation is
    ///         meant to be unbuyable, and this is the one call that can issue it by
    ///         decree. The delay exists so such a change is visible before it lands.
    uint64 public constant ADMIN_DELAY = 48 hours;

    struct PendingMarket {
        address market;
        bool allowed;
        uint64 eta;
    }

    PendingMarket public pendingMarket;

    event MarketChangeProposed(address indexed market, bool allowed, uint64 eta);

    /// @notice True once the deploy-time market has been wired in. Guards a one-shot
    ///         bootstrap: the market cannot be passed to the constructor because it needs
    ///         this contract's address first.
    bool public marketInitialized;

    constructor(address owner_) Ownable(owner_) {}

    /// @notice Authorise the market deployed alongside this contract. Callable once, at
    ///         deployment. Every later change to minting authority goes through the
    ///         timelock, so this cannot be used to quietly add a minter afterwards.
    function initializeMarket(address market) external onlyOwner {
        require(!marketInitialized, "already initialised");
        require(market != address(0), "zero market");
        marketInitialized = true;
        isMarket[market] = true;
        emit MarketSet(market, true);
    }

    modifier onlyMarket() {
        require(isMarket[msg.sender], "rep: not market");
        _;
    }

    /// @notice Queue a change to minting authority. Takes effect after ADMIN_DELAY.
    function proposeMarket(address market, bool allowed) external onlyOwner {
        pendingMarket = PendingMarket(market, allowed, uint64(block.timestamp) + ADMIN_DELAY);
        emit MarketChangeProposed(market, allowed, pendingMarket.eta);
    }

    /// @notice Apply a queued change once its delay has elapsed.
    function executeMarketChange() external onlyOwner {
        PendingMarket memory p = pendingMarket;
        require(p.eta != 0, "nothing pending");
        require(block.timestamp >= p.eta, "timelocked");
        isMarket[p.market] = p.allowed;
        delete pendingMarket;
        emit MarketSet(p.market, p.allowed);
    }

    /// @notice Abandon a queued change. Revoking is always safe to do immediately, so
    ///         an owner who queued something they regret is not forced to wait it out.
    function cancelMarketChange() external onlyOwner {
        delete pendingMarket;
    }

    /// @notice Award Reps. Callable only by authorised markets. Resets the decay clock.
    function award(address account, uint256 amount) external onlyMarket {
        if (amount == 0) return;
        // Fold the decay accrued so far into the stored total before adding, so a long
        // absence isn't undone by a single small award.
        uint256 carried = repOf(account);
        lifetimeRep[account] = carried + amount;
        lastAwardAt[account] = uint64(block.timestamp);
        totalRep += amount;
        emit RepAwarded(account, amount, lifetimeRep[account]);
    }

    /// @notice Decay-adjusted reputation — this is what gates access and weights votes.
    function repOf(address account) public view returns (uint256) {
        uint256 r = lifetimeRep[account];
        if (r == 0) return 0;
        uint64 last = lastAwardAt[account];
        if (last == 0 || block.timestamp <= last) return r;
        uint256 halvings = (block.timestamp - last) / HALF_LIFE;
        if (halvings >= 256) return 0;
        return r >> halvings;
    }
}
