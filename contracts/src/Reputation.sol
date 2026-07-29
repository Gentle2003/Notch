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

    constructor(address owner_) Ownable(owner_) {}

    modifier onlyMarket() {
        require(isMarket[msg.sender], "rep: not market");
        _;
    }

    /// @notice Authorise (or revoke) a market contract that may award Reps.
    function setMarket(address market, bool allowed) external onlyOwner {
        isMarket[market] = allowed;
        emit MarketSet(market, allowed);
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
