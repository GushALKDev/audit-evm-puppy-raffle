<p align="center">
<img src="./images/puppy-raffle.svg" width="400" alt="puppy-raffle">
<br/>

# 🔐 Puppy Raffle Security Audit

A comprehensive security audit of the **PuppyRaffle** smart contract, conducted as part of the [Cyfrin Updraft Security Course](https://updraft.cyfrin.io/).

**Lead Security Researcher:** [GushALKDev](https://github.com/GushALKDev)

---

## 📋 Table of Contents

- [Audit Overview](#audit-overview)
- [📄 Full Audit Report (PDF)](#-full-audit-report-pdf)
- [Severity Classification](#severity-classification)
- [Executive Summary](#executive-summary)
- [Findings](#findings)
  - [High Severity](#-high-severity)
  - [Medium Severity](#-medium-severity)
  - [Low Severity](#-low-severity)
  - [Gas Optimizations](#-gas-optimizations)
  - [Informational](#-informational)
- [Section 4 NFT Exploit Challenge](#-section-4-nft-exploit-challenge)
- [Tools Used](#-tools-used)
- [Lessons Learned](#-lessons-learned)

---

## Audit Overview

| Item | Detail |
|------|--------|
| **Audit Commit Hash** | `2a47715b30cf11ca82db148704e67652ad679cd8` |
| **Solidity Version** | `0.7.6` |
| **Target Chain** | Ethereum Mainnet |
| **Scope** | `src/PuppyRaffle.sol` |
| **Methods** | Manual Review, Static Analysis (Slither, Aderyn) |

---

## 📄 Full Audit Report (PDF)

> **[📥 Download the Complete Audit Report (PDF)](./audit-data/report.pdf)**

The full report contains detailed findings with complete Proof of Concept code, diff patches, and comprehensive recommendations.

---

## Severity Classification

| Severity | Impact |
|----------|--------|
| 🔴 **High** | Critical vulnerabilities leading to direct loss of funds or complete compromise |
| 🟠 **Medium** | Issues causing unexpected behavior or moderate financial impact |
| 🟡 **Low** | Minor issues that don't directly risk funds |
| ⚪ **Gas** | Optimizations to reduce gas consumption |
| 🔵 **Info** | Best practices and code quality improvements |

---

## Executive Summary

The **PuppyRaffle** contract contains **critical security vulnerabilities** that make it **unsafe for production deployment**.

### Key Metrics

| Severity | Count |
|----------|-------|
| 🔴 High | 2 |
| 🟠 Medium | 3 |
| 🟡 Low | 4 |
| ⚪ Gas | 2 |
| 🔵 Info | 10 |
| **Total** | **21** |

### Critical Risks

- ⚠️ **Reentrancy attack** in `refund()` — can drain entire prize pool
- ⚠️ **Weak randomness** — winner/rarity can be predicted and manipulated
- ⚠️ **Integer overflow** — `uint64` fee truncation locks withdrawals
- ⚠️ **Forced ETH** — `selfdestruct` permanently locks fees
- ⚠️ **DoS vulnerability** — O(n²) loop makes raffle unusable

---

## Findings

### 🔴 High Severity

| ID | Finding | Location |
|----|---------|----------|
| H-1 | Reentrancy in `refund()` allows draining all funds | `refund()` |
| H-2 | Weak on-chain randomness allows winner manipulation | `selectWinner()` |

---

### 🟠 Medium Severity

| ID | Finding | Location |
|----|---------|----------|
| M-1 | DoS via O(n²) duplicate check loop | `enterRaffle()` |
| M-2 | `uint64 totalFees` overflow breaks withdrawals | `selectWinner()` |
| M-3 | Forced ETH via `selfdestruct` locks fees forever | `withdrawFees()` |

---

### 🟡 Low Severity

| ID | Finding | Location |
|----|---------|----------|
| L-1 | `getActivePlayerIndex()` returns 0 for both first player and non-existent players | `getActivePlayerIndex()` |
| L-2 | `enterRaffle()` allows empty `newPlayers` array (spam events) | `enterRaffle()` |
| L-3 | Missing zero-address check for `feeAddress` — fees can be burned | Constructor, `changeFeeAddress()` |
| L-4 | `selectWinner()` doesn't follow strict CEI — reentrancy into `enterRaffle` possible | `selectWinner()` |

---

### ⚪ Gas Optimizations

| ID | Finding |
|----|---------|
| G-1 | `raffleDuration` could be `immutable`; image URIs could be `constant` |
| G-2 | Cache `players.length` in loops to avoid repeated storage reads |

---

### 🔵 Informational

| ID | Finding |
|----|---------|
| I-1 | Floating pragma `^0.7.6` should be locked |
| I-2 | Using Solidity 0.7.x misses built-in overflow checks |
| I-3 | `selectWinner()` uses derived accounting instead of `address(this).balance` |
| I-4 | Magic numbers (80/20/100) should be named constants |
| I-5 | Missing events for `selectWinner()` and `withdrawFees()` |
| I-6 | Unused function `_isActivePlayer()` is dead code |
| I-7 | Test coverage is low |
| I-8 | Naming conventions for immutables/storage are inconsistent |
| I-9 | `fee` can be computed as `totalAmountCollected - prizePool` |
| I-10 | `withdrawFees()` MEV considerations should be documented |

---

## 🎯 Section 4 NFT Exploit Challenge

![NFT Exploit Challenge](./images/S4_NFT.png)

Successfully exploited a CTF challenge using weak on-chain randomness. The challenge used:

```solidity
uint256 rng = uint256(keccak256(abi.encodePacked(
    msg.sender, block.prevrandao, block.timestamp
))) % 1_000_000;
```

### Exploit Strategy

Since `msg.sender` is the contract address (not EOA), and block values are known during execution, we can compute the exact "random" number in the same transaction.

### Attack Contract

See [`section-4-nft-exploit/AttackerContract.sol`](./section-4-nft-exploit/AttackerContract.sol):

```solidity
function go() external {
    // Compute the same RNG the challenge will use
    uint256 rng = uint256(keccak256(abi.encodePacked(
        address(this), block.prevrandao, block.timestamp
    ))) % 1_000_000;
    
    IS4(s4).solveChallenge(rng, twitterHandle);  // Guaranteed win!
}
```

### Attack Flow

```
┌─────────────┐     1. attack()      ┌──────────────┐
│   EOA       │─────────────────────▶│  S4Attacker  │
└─────────────┘                      └──────┬───────┘
                                            │
                                            │ 2. solveChallenge(0, handle)
                                            ▼
                                     ┌──────────────┐
                                     │  S4 Contract │
                                     └──────┬───────┘
                                            │
                                            │ 3. Low-level call → go()
                                            ▼
                                     ┌──────────────┐
                                     │  S4Attacker  │ ← Computes exact RNG
                                     └──────┬───────┘
                                            │
                                            │ 4. solveChallenge(correct_rng, handle)
                                            ▼
                                     ┌──────────────┐
                                     │  S4 Contract │ ← Challenge solved! 🎉
                                     └──────────────┘
                                            │
                                            │ 5. NFT minted to S4Attacker
                                            ▼
                                     ┌─────────────┐
                                     │   Profit!   │
                                     └─────────────┘
```

> **Key Insight:** On-chain "randomness" is deterministic when all inputs are known or controllable.

---

## 🛠 Tools Used

| Tool | Purpose |
|------|---------|
| [Foundry](https://github.com/foundry-rs/foundry) | Testing & local development |
| [Slither](https://github.com/crytic/slither) | Static analysis |
| [Aderyn](https://github.com/Cyfrin/aderyn) | Smart contract analyzer |
| [Solidity Visual Developer](https://marketplace.visualstudio.com/items?itemName=tintinweb.solidity-visual-auditor) | VS Code audit annotations |

---

## 📚 Lessons Learned

### Core Security Patterns

1. **CEI (Checks-Effects-Interactions)** — State updates before external calls
2. **Never trust on-chain randomness** — `block.*` values are predictable/manipulable
3. **Avoid strict balance equality** — ETH can be force-sent via `selfdestruct`
4. **Mind integer boundaries** — Especially pre-0.8.0 Solidity (no overflow checks)
5. **Beware O(n²) loops** — Gas exhaustion = DoS attack vector

### Audit Process

```
Scoping → Reconnaissance → Manual Review → Write PoCs → Report
```

---

## 📄 License

This audit report is for **educational purposes only** as part of the Cyfrin Updraft Security Course.

---

<p align="center">
Made with ❤️ while learning Smart Contract Security
</p>
