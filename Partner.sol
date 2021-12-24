// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Partner is AccessControl {
    bytes32 public constant PROPOSAL_ROLE = keccak256("PROPOSAL_ROLE");

    //End time of current cycle leaderboard
    uint32 public currentCycleTime;
    //End time of last cycle leaderboard
    uint32 public lastCycleTime;
    //Invitation leaderboard cycle
    uint32 public cycle = 1 weeks;
    //Membership fees
    uint256 public entranceFee = 0.1 ether;
    //Membership fee increments each time
    uint256 private incrementalFee = 0.05 ether;
    //The membership fee will not increase after being increased to the maximum
    uint256 private incrementalToMaxEntranceFee = 0.5 ether;
    //Each additional 1,000 members will increase the membership fee
    uint256 private incrementalPeriod = 1000;
    //This week’s invitation leaderboard bonus pool
    uint256 public currentPrizePool;
    //Last week invitation leaderboard bonus pool
    uint256 public lastPrizePool;
    //Rewards issued in the previous period
    uint256 public lastIssuedPrize;
    //Becoming a member will be issued a token reward of 1000 times the membership fee
    uint256 private tokenAward = 1000;
    //Total token rewards
    uint256 private tokenAwardTotal = 30000000 ether;
    //Total amount of issued token rewards
    uint256 private issuedTokenAwardTotal = 0;
    //The number of tokens that need to be locked for new proposals and voting
    uint256 public minHeldAward = 100 ether;
    //Token time required for new proposals and voting
    uint256 public lockTime = 1 weeks;
    //The number of members who do not need to be recommended
    uint256 private firstMembers = 1000;
    //tax (%)
    uint256 public tax = 10;
    //Invitation level restriction
    uint256 public invitationLevel = 3;
    //Number of leaderboards
    uint256 public leaderboards = 10;
    //Unlock ratio (%)
    uint256 public unlockRatio = 0;
    //Current cycle leaderboard number
    uint256 public leaderboardNo = 1;
    //Number of marketers
    uint256 public marketersMinInvitation = 3;
    //Number of marketers
    uint256 public marketersNumber = 500;
    //Inject into the leaderboard bonus pool or liquidity pool
    uint256 public poolSwitch = 0;

    //Leaderboard reward ratio
    uint256[] public leaderboardReward = [30, 15, 10, 8, 8, 7, 7, 5, 5, 5];
    //Last leaderboard reward ratio
    uint256[] public lastLeaderboardReward = [30, 15, 10, 8, 8, 7, 7, 5, 5, 5];
    //Invited member reward ratio
    uint256[] public invitationReward = [40, 20, 10];
    //liquidity reward ratio
    uint256[] public liquidityReward = [50, 30, 20];
    //member list
    address[] public memberList;
    //marketers list
    address[] public marketersList;
    //Leaderboard No. 1
    address[] public leaderboardNo1;
    //Leaderboard No. 2
    address[] public leaderboardNo2;

    //Tax pool
    address public taxAddress;
    //Liquidity pool
    address public liquidityAddress;
    //token address
    address public tokenAddress;

    struct MemberInfo {
        uint32 lockTime;  //Token lock-up time required for voting
        uint32 receiveTime;  //Liquidity reward collection time
        uint256 BNBRewards;  //BNB Rewards
        uint256 tokenRewards;  //Token Rewards
        uint256 liquidityRewards;  //Liquidity Rewards
        uint256 tokenWithdraw;  //Cumulative withdrawal amount
        bool isMember;
    }

    struct InviterInfo {
        uint16 currentCycleNumber;  //Number of invitations in the last cycle
        uint32 currentCycleTime;  //End time of current cycle leaderboard
        uint32 totalNumber;  //Total number of invited members
        bool isReceive;  //Has the reward been received
    }

    //Invitation relationship mapping: Invitees => Invite people
    mapping (address => address) public invitationInfo;
    //Invitation relationship mapping: Invite people => Invitees
    mapping (address => address[]) public invitationList;
    //marketers mapping
    mapping (address => bool) public marketersListMapping;
    //Member information
    mapping (address => MemberInfo) public memberData;
    //Inviter informations
    mapping (address => InviterInfo) public memberInviterInfo;

    //Token contract
    IERC20 internal GovernanceToken;

    event Join(address indexed member, uint256 entranceFee);
    event BindParent(address indexed member, address indexed parent);
    event NewInviter(address indexed member, address indexed lower, uint32 indexed time);
    event EditSettingsByInt(string indexed setting, address operator, uint256 value);
    event EditSettingsByIntArray(string indexed setting, address operator, uint256[] value);
    event Dividends(address sender, uint256 dividends);
    event Pledge(address indexed member, uint256 amount);

    event Withdraw(address indexed member, uint256 amount);
    event WithdrawToken(address indexed member, uint256 amount);
    event WithdrawDividends(address indexed member, uint256 amount);

    modifier marketersLimit() {
        if(marketersListMapping[msg.sender]){
            require(memberInviterInfo[msg.sender].totalNumber > marketersMinInvitation, "Ownable: caller is not the owner");
        }
        _;
    }

    constructor() {
        //Initialize the start time of the leaderboard cycle
        currentCycleTime = uint32(block.timestamp) - uint32(block.timestamp) % cycle;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        leaderboardNo1 = new address[](leaderboards);
        leaderboardNo2 = new address[](leaderboards);
    }

    receive() external payable {}

    fallback() external payable {}

    //become member
    function join() external payable {
        require(msg.value == entranceFee, "Your balance is wrong.");
        require(!memberData[msg.sender].isMember, "You are already a member");
        if(getMembersTotal() > firstMembers && invitationInfo[msg.sender] == address(0)){
            revert("Referrer needed");
        }
        
        uint256 _tokenAward = tokenAward * entranceFee;
        if(tokenAwardTotal - issuedTokenAwardTotal < _tokenAward){
            _tokenAward = tokenAwardTotal - issuedTokenAwardTotal;
        }
        issuedTokenAwardTotal += _tokenAward;
        //Add member information
        memberData[msg.sender] = MemberInfo(0, 0, 0, _tokenAward, 0, 0, true);
        memberList.push(msg.sender);
        _updateCurrentCycle();
        
        //Distribute invitation rewards to superiors
        address superior = invitationInfo[msg.sender];
        uint256 rewardsTotal = 0;
        if(superior != address(0)){
            //Update parent invitation data
            if(memberInviterInfo[superior].currentCycleTime == currentCycleTime){
                memberInviterInfo[superior].currentCycleNumber++;
            }else{
                memberInviterInfo[superior].currentCycleTime = currentCycleTime;
                memberInviterInfo[superior].currentCycleNumber = 1;
                memberInviterInfo[superior].isReceive = false;
            }
            memberInviterInfo[superior].totalNumber++;

            _updateLeaderboard(superior);

            //BNB rewards
            for (uint256 i = 0; i < invitationLevel; i++) {
                uint256 currentReward = entranceFee * invitationReward[i] / 100;
                memberData[superior].BNBRewards += currentReward;
                rewardsTotal += currentReward;
                if(invitationInfo[superior] != address(0)){
                    superior = invitationInfo[superior];
                }else{
                    i = invitationLevel;
                }
            }
            
            emit NewInviter(superior, msg.sender, currentCycleTime);
        }

        require(rewardsTotal <= entranceFee, "Setting error");
        uint256 remainingFee = entranceFee - rewardsTotal;

        //Inject the remaining funds into the leaderboard reward pool or liquidity pool
        if(poolSwitch == 1){
            currentPrizePool = currentPrizePool + remainingFee;
        }else if(remainingFee > 0){
            payable(liquidityAddress).transfer(remainingFee);
        }

        emit Join(msg.sender, entranceFee);

        //Update membership Fee
        if(getMembersTotal() % incrementalPeriod == incrementalPeriod - 1 && entranceFee < incrementalToMaxEntranceFee){
            entranceFee += incrementalFee;
        }
    }

    //Bind parent address
    function bindParent(address parentAddress) external {
        require(memberData[parentAddress].isMember, "Inviter error");
        require(!memberData[msg.sender].isMember, "Inviter error");
        require(invitationInfo[msg.sender] == address(0), "Parent bound");
        invitationInfo[msg.sender] = parentAddress;
        invitationList[parentAddress].push(msg.sender);
        emit BindParent(msg.sender, parentAddress);
    }

    function setMarketersList(address[] memory _marketersList) external {
        for(uint256 i = 0; i < _marketersList.length; i++){
            if(!memberData[_marketersList[i]].isMember && marketersList.length < marketersNumber){
                marketersList.push(_marketersList[i]);
                marketersListMapping[_marketersList[i]] = true;

                uint256 _tokenAward = minHeldAward;
                if(tokenAwardTotal - issuedTokenAwardTotal < _tokenAward){
                    _tokenAward = tokenAwardTotal - issuedTokenAwardTotal;
                }
                issuedTokenAwardTotal += _tokenAward;
                memberData[_marketersList[i]] = MemberInfo(0, 0, 0, _tokenAward, 0, 0, true);
                memberList.push(_marketersList[i]);

                if(getMembersTotal() % incrementalPeriod == incrementalPeriod - 1 && entranceFee < incrementalToMaxEntranceFee){
                    entranceFee += incrementalFee;
                }
            }
        }
    }

    //Get the leaderboard
    function getLeaderboard(uint32 findCycleTime) external view returns (address[] memory addressList, uint32[] memory num) {
        address[] memory leaderboardAddress = new address[](leaderboards);
        uint32[] memory leaderboardNum = new uint32[](leaderboards);
        
        if(leaderboardNo == 1){
            if(findCycleTime == currentCycleTime){
                for (uint256 i = 0; i < leaderboards; i++) {
                    leaderboardAddress[i] = leaderboardNo1[i];
                    leaderboardNum[i] = memberInviterInfo[leaderboardNo1[i]].currentCycleNumber;
                }
            }
            if(findCycleTime == lastCycleTime){
                for (uint256 i = 0; i < leaderboards; i++) {
                    leaderboardAddress[i] = leaderboardNo2[i];
                    leaderboardNum[i] = memberInviterInfo[leaderboardNo2[i]].currentCycleNumber;
                }
            }
        }else{
            if(findCycleTime == currentCycleTime){
                for (uint256 i = 0; i < leaderboards; i++) {
                    leaderboardAddress[i] = leaderboardNo2[i];
                    leaderboardNum[i] = memberInviterInfo[leaderboardNo2[i]].currentCycleNumber;
                }
            }
            if(findCycleTime == lastCycleTime){
                for (uint256 i = 0; i < leaderboards; i++) {
                    leaderboardAddress[i] = leaderboardNo1[i];
                    leaderboardNum[i] = memberInviterInfo[leaderboardNo1[i]].currentCycleNumber;
                }
            }
        }
        return (leaderboardAddress, leaderboardNum);
    }

    //Get leaderboard rewards
    function getLeaderboardRewards() external {
        _updateCurrentCycle();
        uint256 rank = getRank(msg.sender, lastCycleTime);
        require(rank > 0, "Not on the list");
        require(memberInviterInfo[msg.sender].isReceive != true, "Reward has been collected");
        uint256 lastReward = lastLeaderboardReward[rank - 1] * lastPrizePool / 100;
        require(lastIssuedPrize + lastReward <= lastPrizePool, "Bonus has expired");
        memberInviterInfo[msg.sender].isReceive = true;
        lastIssuedPrize += lastReward;
        _withdraw(lastReward);
    }

    //Withdraw BNB
    function withdraw() external {
        require(memberData[msg.sender].BNBRewards > 0 , "Insufficient amount");
        _withdraw(memberData[msg.sender].BNBRewards);
        memberData[msg.sender].BNBRewards = 0;
    }

    //Withdraw Token
    function withdrawToken() external marketersLimit {
        uint256 amount = (memberData[msg.sender].tokenRewards + memberData[msg.sender].tokenWithdraw) * unlockRatio / 100 - memberData[msg.sender].tokenWithdraw ;
        if(memberData[msg.sender].lockTime > block.timestamp){
            unchecked { amount -= minHeldAward; }
        }
        require(amount > 0 , "Insufficient cash balance");
        
        GovernanceToken.transfer(msg.sender, amount);
        memberData[msg.sender].tokenRewards -= amount;
        memberData[msg.sender].tokenWithdraw += amount;

        emit WithdrawToken(msg.sender, amount);
    }

    //Tokens required for pledge voting
    function pledge() external {
        require(memberData[msg.sender].tokenRewards < minHeldAward , "The pledged tokens are enough");
        GovernanceToken.transferFrom(msg.sender, address(this), minHeldAward - memberData[msg.sender].tokenRewards);
        memberData[msg.sender].tokenRewards = minHeldAward;
        memberData[msg.sender].lockTime = uint32(block.timestamp + lockTime);

        emit Pledge(msg.sender, minHeldAward);
    }

    //Liquidity Dividend
    function dividends(address sender, uint256 _toAwardFee) external {
        require(msg.sender == tokenAddress);
        for(uint256 i = 0; i < invitationLevel; i++){
            if(invitationInfo[sender] != address(0)){
                memberData[invitationInfo[sender]].liquidityRewards = memberData[invitationInfo[sender]].liquidityRewards + _toAwardFee * liquidityReward[i] / 100;
                sender = invitationInfo[sender];
            }else{
                break;
            }
        }

        emit Dividends(sender, _toAwardFee);
    }

    //Withdraw dividends
    function withdrawDividends() external marketersLimit {
        require(memberData[msg.sender].liquidityRewards > 0 , "Insufficient cash balance");
        require(memberData[msg.sender].receiveTime < block.timestamp , "Can't withdraw cash temporarily");
        
        GovernanceToken.transferFrom(tokenAddress, msg.sender, memberData[msg.sender].liquidityRewards);
        emit WithdrawDividends(msg.sender, memberData[msg.sender].liquidityRewards);
        memberData[msg.sender].liquidityRewards = 0;
        memberData[msg.sender].receiveTime = uint32(block.timestamp + 1 days);
    }

    //Returns the number of remaining tokens that the contract is allowed to spend on behalf of the owner.
    function allowance(address owner) external view returns (uint256) {
        return GovernanceToken.allowance(owner, address(this));
    }

    //Get leaderboard rewards
    function getLeaderboardRewardRatio() public view returns (uint256[] memory currentLeaderboardRewards, uint256[] memory lastLeaderboardRewards) {
        uint256[] memory _currentLeaderboardReward = new uint256[](leaderboards);
        uint256[] memory _lastLeaderboardReward = new uint256[](leaderboards);
        for (uint256 i = 0; i < leaderboards; i++){
            _currentLeaderboardReward[i] = leaderboardReward[i];
            _lastLeaderboardReward[i] = lastLeaderboardReward[i];
        }
        return (_currentLeaderboardReward, _lastLeaderboardReward);
    }

    //My subordinate information
    function getSubordinateInfo() public view returns (uint256 level1, uint256 level2, uint256 level3) {
        uint256 level1Num = invitationList[msg.sender].length;
        uint256 level2Num = 0;
        uint256 level3Num = 0;
        for (uint256 i = 0; i < level1Num; i++){
            level2Num += invitationList[invitationList[msg.sender][i]].length;
            for (uint256 j = 0; j < invitationList[invitationList[msg.sender][i]].length; j++){
                level3Num += invitationList[invitationList[invitationList[msg.sender][i]][j]].length;
            }
        }
        return (level1Num, level2Num, level3Num);
    }

    //Get the invitation relationship chain
    function getRelationshipChain(address target) public view returns (address[] memory addressList) {
        address[] memory relationshipChain = new address[](invitationLevel);
        for (uint256 i = 0; i < invitationLevel; i++){
            relationshipChain[i] = invitationInfo[target];
            target = invitationInfo[target];
        }
        return relationshipChain;
    }

    //Get the ranking of the specified address
    function getRank(address target, uint32 findCycleTime) public view returns (uint256 _rank) {
        if(leaderboardNo == 1){
            if(findCycleTime == currentCycleTime){
                for (uint256 i = 0; i < leaderboards; i++) {
                    if(target == leaderboardNo1[i]){
                        return  i + 1;
                    }
                }
            }
            if(findCycleTime == lastCycleTime){
                for (uint256 i = 0; i < leaderboards; i++) {
                    if(target == leaderboardNo2[i]){
                        return  i + 1;
                    }
                }
            }
        }else{
            if(findCycleTime == currentCycleTime){
                for (uint256 i = 0; i < leaderboards; i++) {
                    if(target == leaderboardNo2[i]){
                        return  i + 1;
                    }
                }
            }
            if(findCycleTime == lastCycleTime){
                for (uint256 i = 0; i < leaderboards; i++) {
                    if(target == leaderboardNo1[i]){
                        return  i + 1;
                    }
                }
            }
        }
        return 0;
    }

    //Set the leaderboard cycle
    function setCycle(uint32 newCycle) public onlyRole(PROPOSAL_ROLE) {
        require(cycle != newCycle);
        cycle = newCycle;
        emit EditSettingsByInt("setCycle", msg.sender, newCycle);
    }

    //Set incremental membership fee
    function setIncrementalFee(uint256 newIncrementalFee) public onlyRole(PROPOSAL_ROLE) {
        require(incrementalFee != newIncrementalFee);
        incrementalFee = newIncrementalFee;
        emit EditSettingsByInt("setIncrementalFee", msg.sender, newIncrementalFee);
    }

    //Set membership fee
    function setEntranceFee(uint256 newEntranceFee) public onlyRole(PROPOSAL_ROLE) {
        require(entranceFee != newEntranceFee);
        entranceFee = newEntranceFee;
        emit EditSettingsByInt("setEntranceFee", msg.sender, newEntranceFee);
    }

    //Set to increase to the maximum membership fee
    function setIncrementalToMaxEntranceFee(uint256 newIncrementalToMaxEntranceFee) public onlyRole(PROPOSAL_ROLE) {
        require(incrementalToMaxEntranceFee != newIncrementalToMaxEntranceFee);
        incrementalToMaxEntranceFee = newIncrementalToMaxEntranceFee;
        emit EditSettingsByInt("setIncrementalToMaxEntranceFee", msg.sender, newIncrementalToMaxEntranceFee);
    }

    //Set increment period
    function setIncrementalPeriod(uint256 newIncrementalPeriod) public onlyRole(PROPOSAL_ROLE) {
        require(incrementalPeriod != newIncrementalPeriod);
        incrementalPeriod = newIncrementalPeriod;
        emit EditSettingsByInt("setIncrementalPeriod", msg.sender, newIncrementalPeriod);
    }

    //Set up token rewards
    function setTokenAward(uint256 newTokenAward) public onlyRole(PROPOSAL_ROLE) {
        require(tokenAward != newTokenAward);
        tokenAward = newTokenAward;
        emit EditSettingsByInt("setTokenAward", msg.sender, newTokenAward);
    }

    //Set the number of tokens that need to be locked for new proposals and voting
    function setMinHeldAward(uint256 newMinHeldAward) public onlyRole(PROPOSAL_ROLE) {
        require(minHeldAward != newMinHeldAward);
        minHeldAward = newMinHeldAward;
        emit EditSettingsByInt("setMinHeldAward", msg.sender, newMinHeldAward);
    }

    //Set Token time required for new proposals and voting
    function setLockTime(uint256 newLockTime) public onlyRole(PROPOSAL_ROLE) {
        require(lockTime != newLockTime);
        lockTime = newLockTime;
        emit EditSettingsByInt("setLockTime", msg.sender, newLockTime);
    }

    //Set the number of members who do not need to be recommended
    function setFirstMembers(uint256 newFirstMembers) public onlyRole(PROPOSAL_ROLE) {
        require(firstMembers != newFirstMembers);
        firstMembers = newFirstMembers;
        emit EditSettingsByInt("setFirstMembers", msg.sender, newFirstMembers);
    }

    //Set tax
    function setTax(uint256 newTax) public onlyRole(PROPOSAL_ROLE) {
        require(tax != newTax);
        tax = newTax;
        emit EditSettingsByInt("setTax", msg.sender, newTax);
    }

    //Set unlock ratio
    function setUnlockRatio(uint256 newUnlockRatio) public onlyRole(PROPOSAL_ROLE) {
        require(newUnlockRatio <= 100);
        require(unlockRatio != newUnlockRatio);
        unlockRatio = newUnlockRatio;
        emit EditSettingsByInt("sesetUnlockRatiotTax", msg.sender, newUnlockRatio);
    }

    //Set inject the leaderboard bonus pool or liquidity pool
    function setPoolSwitch(uint256 newPoolSwitch) public onlyRole(PROPOSAL_ROLE) {
        require(poolSwitch != newPoolSwitch);
        poolSwitch = newPoolSwitch;
        emit EditSettingsByInt("setPoolSwitch", msg.sender, newPoolSwitch);
    }

    //Set tax address
    function setTaxAddress(address _taxAddress) public onlyRole(PROPOSAL_ROLE) {
        require(taxAddress != _taxAddress);
        taxAddress = _taxAddress;
    }

    //Set liquidity address
    function setLiquidityAddress(address _liquidityAddress) public onlyRole(PROPOSAL_ROLE) {
        require(liquidityAddress != _liquidityAddress);
        liquidityAddress = _liquidityAddress;
    }

    //Set token address
    function setTokenAddress(address _tokenAddress) public onlyRole(PROPOSAL_ROLE) {
        require(tokenAddress != _tokenAddress, "This address was already used");
        tokenAddress = _tokenAddress;
        GovernanceToken = IERC20(tokenAddress);
    }

    //Set invitation level restrictions
    function setInvitationLevel(uint256 newInvitationLevel, uint256[] memory newInvitationReward) public onlyRole(PROPOSAL_ROLE) {
        uint256 totalNewReward = 0;
        for (uint256 i = 0; i < newInvitationLevel; i++) {
            totalNewReward += newInvitationReward[i];
        }
        require(totalNewReward <= 100, "newInvitationReward The proportion is too large");
        
        invitationLevel = newInvitationLevel;
        invitationReward = newInvitationReward;

        emit EditSettingsByInt("setInvitationLevel", msg.sender, newInvitationLevel);
        emit EditSettingsByIntArray("newInvitationReward", msg.sender, newInvitationReward);
    }

    //Number of leaderboards
    function setLeaderboards(uint256 newLeaderboards, uint256[] memory newLeaderboardReward, uint256[] memory newLiquidityReward) public onlyRole(PROPOSAL_ROLE) {
        uint256 totalNewReward = 0;
        for (uint256 i = 0; i < newLeaderboards; i++) {
            totalNewReward += newLeaderboardReward[i];
        }
        require(totalNewReward <= 100, "The proportion is too large");
        totalNewReward = 0;
        for (uint256 i = 0; i < newLeaderboards; i++) {
            totalNewReward += newLiquidityReward[i];
        }
        require(totalNewReward <= 100, "The proportion is too large");
        leaderboards = newLeaderboards;
        leaderboardReward = newLeaderboardReward;
        liquidityReward = newLiquidityReward;

        emit EditSettingsByInt("setLeaderboards", msg.sender, newLeaderboards);
        emit EditSettingsByIntArray("newLeaderboardReward", msg.sender, newLeaderboardReward);
        emit EditSettingsByIntArray("newLiquidityReward", msg.sender, newLiquidityReward);
    }

    //Get the total number of members
    function getMembersTotal() public view returns (uint256) {
        return memberList.length;
    }

    //Update the end time of the invitation leaderboard statistical period
    function _updateCurrentCycle() internal {
        if(currentCycleTime < block.timestamp){
            lastCycleTime = currentCycleTime;
            uint32 multiple = uint32(block.timestamp - currentCycleTime + cycle - 1) / cycle;
            currentCycleTime = currentCycleTime + cycle * multiple;
            unchecked { lastPrizePool = currentPrizePool + lastPrizePool - lastIssuedPrize; }
            lastIssuedPrize = 0;
            currentPrizePool = 0;
            leaderboardNo = leaderboardNo == 1 ? 2 : 1;
            lastLeaderboardReward = leaderboardReward;
            if(leaderboardNo == 1){
                leaderboardNo1 = new address[](leaderboards);
            }else{
                leaderboardNo2 = new address[](leaderboards);
            }
        }
    }

    //Withdraw BNB
    function _withdraw(uint256 amount) private {
        uint256 taxes = amount * tax / 100;
        uint256 balance;
        unchecked { balance = amount - taxes; }
        payable(taxAddress).transfer(taxes);
        payable(msg.sender).transfer(balance);

        emit Withdraw(msg.sender, amount);
    }

    //Update the leaderboard
    function _updateLeaderboard(address superior) private {
        uint256 cutOff = leaderboards - 1;
        if(leaderboardNo == 1){
            if(
                memberInviterInfo[leaderboardNo1[leaderboards - 1]].currentCycleNumber < memberInviterInfo[superior].currentCycleNumber 
                || memberInviterInfo[leaderboardNo1[leaderboards - 1]].currentCycleTime < currentCycleTime
            ){
                for(uint256 i = 0; i < leaderboards; i++){
                    if(leaderboardNo1[i] == superior){
                        break;
                    }
                    if(
                        memberInviterInfo[leaderboardNo1[i]].currentCycleNumber < memberInviterInfo[superior].currentCycleNumber 
                        || memberInviterInfo[leaderboardNo1[i]].currentCycleTime < currentCycleTime 
                    ){
                        for(uint256 k = i; k < leaderboards; k++){
                            if(memberInviterInfo[leaderboardNo1[k]].currentCycleTime < currentCycleTime || leaderboardNo1[k] == superior){
                                cutOff = k;
                                break;
                            }
                        }
                        for(uint256 j = cutOff; j > i; j--){
                            if(memberInviterInfo[leaderboardNo1[j -1]].currentCycleTime == currentCycleTime){
                                leaderboardNo1[j] = leaderboardNo1[j - 1];
                            }
                        }
                        leaderboardNo1[i] = superior;
                        break;
                    }
                }
            }
        }else{
            if(
                memberInviterInfo[leaderboardNo2[leaderboards - 1]].currentCycleNumber < memberInviterInfo[superior].currentCycleNumber 
                || memberInviterInfo[leaderboardNo2[leaderboards - 1]].currentCycleTime < currentCycleTime
            ){
                for(uint256 i = 0; i < leaderboards; i++){
                    if(leaderboardNo2[i] == superior){
                        break;
                    }
                    if(
                        memberInviterInfo[leaderboardNo2[i]].currentCycleNumber < memberInviterInfo[superior].currentCycleNumber
                        || memberInviterInfo[leaderboardNo2[i]].currentCycleTime < currentCycleTime
                    ){
                        for(uint256 k = i; k < leaderboards; k++){
                            if(memberInviterInfo[leaderboardNo2[k]].currentCycleTime < currentCycleTime || leaderboardNo2[k] == superior){
                                cutOff = k;
                                break;
                            }
                        }
                        for(uint256 j = cutOff; j > i; j--){
                            if(memberInviterInfo[leaderboardNo2[j -1]].currentCycleTime == currentCycleTime){
                                leaderboardNo2[j] = leaderboardNo2[j - 1];
                            }
                        }
                        leaderboardNo2[i] = superior;
                        break;
                    }
                }
            }
        }
    }

}
