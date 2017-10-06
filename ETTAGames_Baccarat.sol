pragma solidity ^0.4.11;

contract EttaBaccarat {

    enum BaccaratBetOptions {
        Unknown,
        Banker,
        Player,
        Tie
    }

    struct GameRound {
        uint roundId;
        address player;
        uint stake;
        BaccaratBetOptions betOption;
        string gameDetail;
        uint8 bankerPoints;
        uint8 playerPoints;
        BaccaratBetOptions winningOption;
        uint winloss;
        bool isSettled;
    }

    /*
     * Game stakeholder
    */
    address public owner;
    address public operator;
    
    /*
     * Game vars
    */
    bool public isActive = true;
    uint public minBet = 50 finney;
    uint public totalPendingPayout = 0;
    uint8 public maxPayoutPercentage = 70;

    mapping(uint8 =>uint16) public oddsTable;
    mapping(uint8 =>uint) public maxBetTable;

    /*
     * Player bets
    */
    mapping(address=>mapping(uint => GameRound)) public playerBets;

    /*
     * Events
    */    
    event onBetPlaced(uint indexed roundId, address indexed player, uint betOption, string orderDetail, uint stake);
    event onBetSettled(uint indexed roundId, address indexed player, uint returnToPlayer);
    event onBetRefunded(uint indexed roundId, address indexed player, uint amount);
    event onTransferFailed(address receiver, uint amount);
    /*
     * Constructor
    */ 
    function EttaBaccarat(uint minBetInitial, address operatorInitial) payable {
        if (minBetInitial != 0) {
            minBet = minBetInitial;
        }
        if (operatorInitial != 0) {
            operator = operatorInitial;
        } else {
            operator = msg.sender;
        }
        owner = msg.sender;
        
        setUp();
    }

    /*
     * Modifier for ensuring that only the owner can access.
    */   
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    /*
     * Modifier for ensuring that only operators can access.
    */
    modifier onlyOperator{
        require(msg.sender == operator);
        _;       
    }

    /*
     * Modifier for ensuring that this function is only called when player wins the bet.
    */    
    modifier onlyWinningBet(uint winloss) {
        if (winloss > 0) {
            _;
        }
    }

    /*
     * Modifier for ensuring that this function is only called when player loses the bet.
    */
    modifier onlyLosingBet(uint winloss) {
        if (winloss <= 0) {
            _;
        }
    }

    /*
     * Modifier for checking that the game is active.
    */    
    modifier onlyIfActive {
        require(isActive);
        _;
    }

    /*
     * Modifier for checking that the game is inactive.
    */
    modifier onlyIfInactive {
        require(!isActive);
        _;
    }

    /*
     * Modifier for checking that the stake is greater than minimum bet.
    */    
    modifier onlyGreaterThanMinBet {
        if (msg.value < minBet) {
            revert();
        }
        _;
    }

    /*
     * Modifier for checking that the stake is less than maximum bet.
    */ 
    modifier onlySmallerThanMaxBet(uint8 betOption) {
        if (msg.value > maxBetTable[betOption]) {
            revert();
        }
        _;
    }

    /*
     * Modifier for checking that the round ID doesn't repeat.
    */     
    modifier onlyNewRoundId(uint roundId) {
        if (playerBets[msg.sender][roundId].roundId != 0) {
            revert();
        }
        _;
    }

    /*
     * Modifier for checking that the bet is not settled.
    */  
    modifier onlyNotSettled(address player, uint roundId) {
        if (playerBets[player][roundId].roundId == 0 || playerBets[player][roundId].isSettled == true) {
            revert();
        }
        _;
    }  

    event onAffordable(uint balance, uint percentage, uint totalPendingPayoutValue, uint payout, int r1);

    /*
     * Modifier for ensuring that the total payout is still affordable for owner.
    */      
    modifier onlyPendingPayoutAffordable(uint8 betOption) {
        uint processedStakeTimesPercentage = this.balance * maxPayoutPercentage / 100;
        uint tPendingPayout = totalPendingPayout;
        uint payout = getPayout(msg.value, betOption);
        int r1 = int(processedStakeTimesPercentage - tPendingPayout - payout);
        if ( r1 <= 0 ) {
            revert();
        }
        _;
    }

    /*
     * Modifier for the bet option is valid.
    */       
    modifier onlyValidBetOption(uint8 betOption) {
        if (oddsTable[betOption] == 0) {
            revert();
        }
        _;
    }

    /*
     * Public function
     * Only owner can transfer Ether to the contract.
    */    
    function () payable onlyOwner {
        
    }

    /*
     * Private function
     * Initialize odds and maximum bet of each bet option.
    */     
    function setUp() private {
        oddsTable[uint8(BaccaratBetOptions.Banker)] = 195;
        oddsTable[uint8(BaccaratBetOptions.Player)] = 200;
        oddsTable[uint8(BaccaratBetOptions.Tie)] = 900;

        maxBetTable[uint8(BaccaratBetOptions.Banker)] = 2.5 ether;
        maxBetTable[uint8(BaccaratBetOptions.Player)] = 2.5 ether;
        maxBetTable[uint8(BaccaratBetOptions.Tie)] = 312.5 finney;
    }

    /*
     * Public function
     * Betting.
     * Execute when:
     *  - Game is set to active.
     *  - Stake is between minimum bet and maximum bet.
     *  - The total pending payout is affordable for owner.
     *  - Bet option is valid.
     *  - Round ID doesn't exist.
    */   
    function bet(uint8 betOption, string orderDetail, uint roundId) payable onlyIfActive onlyGreaterThanMinBet onlyPendingPayoutAffordable(betOption) onlyValidBetOption(betOption) onlyNewRoundId(roundId) onlySmallerThanMaxBet(betOption) {
        var  gameRound = GameRound(roundId, msg.sender, msg.value, BaccaratBetOptions(betOption), "", 0, 0, BaccaratBetOptions.Unknown, 0, false);
        playerBets[msg.sender][roundId] = gameRound;
        onBetPlaced(roundId, msg.sender, betOption, orderDetail, msg.value);
        totalPendingPayout += getPayout(msg.value, betOption);
    }

    /*
     * Public function
     * For operator to settle the bet.
     * Only operators are authorized to call this function.
     * Execute when the bet has not settled yet.
    */      
    function settle(address player, uint roundId, string gameDetail, uint8 bankerPoints, uint8 playerPoints, uint returnToPlayer) public onlyOperator onlyNotSettled(player, roundId) returns(bool) {
        GameRound storage gameRound = playerBets[player][roundId];
        gameRound.gameDetail = gameDetail;
        gameRound.bankerPoints = bankerPoints;
        gameRound.playerPoints = playerPoints;
        
        determineWinLose(gameRound);
        gameRound.winloss = gameRound.winloss + returnToPlayer;
        settleWinningBet(player, gameRound.winloss);
        settleLosingBet(player, gameRound.winloss);
        gameRound.isSettled = true;
        totalPendingPayout -= getPayout(gameRound.stake, uint8(gameRound.betOption));
        onBetSettled(roundId, player, returnToPlayer);
        return true;
    }

    /*
     * Public function
     * For operator to refund the bet.
     * Only operators are authorized to call this function.
     * Execute when the bet has not settled yet.
    */      
    function refund(address player, uint roundId, uint amount) public onlyOperator onlyNotSettled(player, roundId) returns(bool) {
        GameRound storage gameRound = playerBets[player][roundId];
        gameRound.gameDetail = "";
        gameRound.bankerPoints = 0;
        gameRound.playerPoints = 0;
        
        gameRound.winloss = amount;
        settleWinningBet(player, amount);
        gameRound.isSettled = true;
        totalPendingPayout -= getPayout(gameRound.stake, uint8(gameRound.betOption));
        onBetRefunded(roundId, player, amount);
        return true;
    }

    /*
     * Private function 
     * For operator to settle the bet.
     * Only operators are authorized to call this function.
     * Execute when the bet is a winning bet.
    */       
    function settleWinningBet(address player, uint winloss) private onlyOperator onlyWinningBet(winloss) {
        player.transfer(winloss);
    }

    /*
     * Private function 
     * For operator to settle the bet.
     * Settle the losing bet and transfer 1 Wei back to player.
     * Execute when the bet is a losing bet.
    */       
    function settleLosingBet(address player, uint winloss) private onlyOperator onlyLosingBet(winloss) {
        player.transfer(1);
    }

    /*
     * Private function 
     * The logic for determining the bet is winning or losing and calculating the winloss amount.
     * Only operators are authorized to call this function.
    */   
    function determineWinLose(GameRound storage gameRound) private onlyOperator {
        gameRound.winningOption = getWinningOption(gameRound);
        gameRound.winloss = getWinLoss(gameRound);
    }

    /*
     * Private function 
     * Determine which option is the winning option.
     * Only operators are authorized to call this function.
    */   
    function getWinningOption(GameRound gameRound) private onlyOperator returns(BaccaratBetOptions) {
        uint bp = gameRound.bankerPoints;
        uint pp = gameRound.playerPoints;
        if (bp == pp) {
            return BaccaratBetOptions.Tie;
        }
        if (bp > pp) {
            return BaccaratBetOptions.Banker;
        }
        return BaccaratBetOptions.Player;
    }

    /*
     * Private function 
     * Calculate the win loss amount.
     * Only operators are authorized to call this function.
    */   
    function getWinLoss(GameRound gameRound) private onlyOperator returns(uint) {
        if (gameRound.betOption == gameRound.winningOption) {
            return getPayout(gameRound.stake, uint8(gameRound.winningOption));
        }
        if (gameRound.betOption != BaccaratBetOptions.Tie && gameRound.winningOption == BaccaratBetOptions.Tie) {
            return gameRound.stake;
        }   
        return 0;
    }

    /*
     * Private function 
     * Calculate the estimated payout.
    */      
    function getPayout(uint stake, uint8 betOption) private returns(uint) {
        return stake * oddsTable[betOption] / 100;
    }    

    /*
     * Public function 
     * Activate the game.
     * Only operators are authorized to call this function.
    */      
    function setGameActive() public onlyOperator {
        isActive = true;
    }

    /*
     * Public function 
     * Deactivate the game.
     * Only operators are authorized to call this function.
    */        
    function setGameStopped() public onlyOperator {
        isActive = false;
    }	

    /*
     * Public function 
     * Exclude the commission on Banker option.
     * Only operators are authorized to call this function.
    */ 
    function setBankerNoCommision() public onlyOperator {
        oddsTable[uint8(BaccaratBetOptions.Banker)] = 200;
    }

    /*
     * Public function 
     * Include the commission on Banker option.
     * Only operators are authorized to call this function.
    */ 	    
    function setBankerCommision() public onlyOperator {
        oddsTable[uint8(BaccaratBetOptions.Banker)] = 195;
    }

    /*
     * Public function 
     * Set the affordable payout.
     * Only operators are authorized to call this function.
    */ 
    function setMaxPayoutPercentage(uint8 percentage) public onlyOperator {
        maxPayoutPercentage = percentage;
    }

    /*
     * Public function 
     * Update the maximum bet of particular bet option.
     * Valid bet option only & only operators are authorized to call this function.
    */ 
    function setMaxBetByBetOption(uint8 betOption, uint maxBet) public onlyOperator onlyValidBetOption(betOption) {
        maxBetTable[betOption] = maxBet;
    }

    /*
     * Public function 
     * Update globally the minimum bet to new value.
     * Only operators are authorized to call this function.
    */       
    function setMinBet(uint newMinBet) public onlyOperator {
        minBet = newMinBet;
    }

    /*
     * Public function 
     * Globally update operator
     * Only owner is authorized to call this function.
    */       
    function setOperator(address newOperator) public onlyOwner {
        operator = newOperator;
    }

    /*
     * Public function 
     * Transfer the balance of contract to owner's address.
     * Only owner is authorized to call this function.
    */      
    function transferToOwner(uint amount) public onlyOwner {
        if(int(this.balance - amount - totalPendingPayout) <= 0) {
            onTransferFailed(owner, amount);
            return;
        }
        owner.transfer(amount);
    }

    /*
     * Public function 
     * Destroy the contract.
     * Only owner is authorized to call this function.
    */     
    function ownerkill() public onlyOwner {
		selfdestruct(owner);
	}
}