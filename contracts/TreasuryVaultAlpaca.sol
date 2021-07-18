// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IFairLaunch.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/ITreasury.sol";

contract TreasuryVaultAlpaca is Ownable, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public asset;
    address public ibAsset;
    address public reward;

    address public fairLaunch;
    uint256 public pid;
    address public treasury;

    uint256 public vaultBalance;
    uint256 public ibVaultBalance;
    bool public pauseVault = true; // default pause

    address public share;

    IUniswapV2Router public router;
    address[] public path_alpaca;
    address[] public path_busd;
    uint256 private constant LIMIT_SWAP_TIME = 10 minutes;

    // MODIFIERS
    modifier onlyTreasury {
        require(_msgSender() == treasury, "!treasury");
        _;
    }

    // Constructor
    function initialize(
        address _asset,
        address _ibAsset,
        address _reward,
        address _fairLaunch,
        uint256 _pid,
        address _treasury,
        bool _pauseVault
    ) external initializer onlyOwner {
        require(_asset != address(0), "Invalid address");
        asset = _asset;
        setIbAsset(_ibAsset);
        setReward(_reward);
        setStakingPool(_fairLaunch, _pid);
        setTreasury(_treasury);
        setPauseVault(_pauseVault);
    }

    // TREASURY functions
    function deposit(uint256 _amount) external onlyTreasury {
        require(_amount > 0, "amount = 0");
        require(asset != address(0), "Invalid address");
        require(ibAsset != address(0), "Invalid address");

        IERC20 _asset = IERC20(asset);
        IERC20 _ibAsset = IERC20(ibAsset);

        //step 1. transfer BUSD from treasury to vault
        _asset.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 newBalance = _asset.balanceOf(address(this));
        vaultBalance = newBalance;

        if (pauseVault) {
            // do not invest in next step
            return;
        }

        //step 2. deposit BUSD to ibBUSD
        _asset.safeApprove(address(ibAsset), 0);
        _asset.safeApprove(address(ibAsset), newBalance);
        IVault(ibAsset).deposit(newBalance); // invest everything in vault
        uint256 ibBalance = _ibAsset.balanceOf(address(this));
        ibVaultBalance = ibBalance;

        //step 3. deposit ibBUSD to fairLaunch
        _ibAsset.safeApprove(address(fairLaunch), 0);
        _ibAsset.safeApprove(address(fairLaunch), ibBalance);
        IFairLaunch(fairLaunch).deposit(address(this), pid, ibBalance);

        emit Deposited(_amount);
    }

    function withdraw() external onlyTreasury {
        IERC20 _asset = IERC20(asset);
        IERC20 _ibAsset = IERC20(ibAsset);

        if (ibVaultBalance == 0) {
            // when pauseVault = true, transfer all balance to treasury
            _asset.safeTransfer(treasury, vaultBalance);
            vaultBalance = _asset.balanceOf(address(this));
            return;
        }

        //step 1. withdraw all from fairLaunch
        IFairLaunch(fairLaunch).withdrawAll(address(this), pid);
        uint256 ibBalance = _ibAsset.balanceOf(address(this));

        //step 2. withdraw from ibBUSD to BUSD
        IVault(ibAsset).withdraw(ibBalance); // withdraw to BUSD
        uint256 newBalance = _asset.balanceOf(address(this)); // withdraw everything in vault
        uint256 profit = 0;
        if (newBalance > vaultBalance) {
            profit = newBalance - vaultBalance;
        }

        //step 3. transfer BUSD to treasury
        _asset.safeTransfer(treasury, vaultBalance);

        // swap busd to share
        IERC20(_asset).safeApprove(address(router), 0);
        IERC20(_asset).safeApprove(address(router), profit);
        router.swapExactTokensForTokens(profit, 1, path_busd, address(this), block.timestamp + LIMIT_SWAP_TIME);
        // swap reward to share
        uint256 rewardBalance = getIncentiveRewardBalance();
        IERC20(reward).safeApprove(address(router), 0);
        IERC20(reward).safeApprove(address(router), rewardBalance);
        router.swapExactTokensForTokens(rewardBalance, 1, path_alpaca, address(this), block.timestamp + LIMIT_SWAP_TIME);

        uint256 buyback = IERC20(share).balanceOf(address(this));
        if(buyback > 0){
          _transferShareToReserve(buyback);
        }

        vaultBalance = _asset.balanceOf(address(this));
        ibVaultBalance = _ibAsset.balanceOf(address(this));

        emit Withdrawn(newBalance);

    }

    function getIncentiveRewardBalance() public view returns (uint256) {
        return IERC20(reward).balanceOf(address(this));
    }

    function collateralReserve() public view returns (address) {
        return ITreasury(treasury).collateralReserve();
    }

    function _transferShareToReserve(uint256 _amount) internal {
        address _reserve = collateralReserve();
        require(_reserve != address(0), "Invalid reserve address");
        IERC20(share).safeTransfer(_reserve, _amount);
        emit TransferedShare(_amount);
    }

    // ===== VAULT ADMIN FUNCTIONS =============== //

    function setRouter(address _router, address[] calldata _pathAlpaca, address[] calldata _pathBusd) public onlyOwner {
        require(_router != address(0), "Invalid router");
        router = IUniswapV2Router(_router);
        path_alpaca = _pathAlpaca;
        path_busd = _pathBusd;
        emit SetRouter(_router);
    }

    function setShare(address _share) public onlyOwner {
        require(_share != address(0), "Invalid address");
        share = _share;
        emit ShareUpdated(_share);
    }

    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "Invalid address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setStakingPool(address _fairLaunch, uint256 _pid) public onlyOwner {
        require(_fairLaunch != address(0), "Invalid address");
        fairLaunch = _fairLaunch;
        pid = _pid;
        emit StakingPoolUpdated(_fairLaunch, _pid);
    }

    function setPauseVault(bool _pauseVault) public onlyOwner {
        pauseVault = _pauseVault;
        emit PauseVaultUpdated(_pauseVault);
    }

    function setIbAsset(address _ibAsset) public onlyOwner {
        require(_ibAsset != address(0), "Invalid address");
        ibAsset = _ibAsset;
        emit IbAssetUpdated(_ibAsset);
    }

    function setReward(address _reward) public onlyOwner {
        require(_reward != address(0), "Invalid address");
        reward = _reward;
        emit RewardUpdated(_reward);
    }

    // *** RESCUE FUNCTIONS ***

    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data
    ) public onlyOwner returns (bytes memory) {
        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }
        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, string("TreasuryVaultAave::executeTransaction: Transaction execution reverted."));
        return returnData;
    }

    receive() external payable {}

    /* ========== EVENTS ========== */
    event TreasuryUpdated(address indexed newTreasury);
    event StakingPoolUpdated(address indexed newFairLaunch, uint256 newPid);
    event PauseVaultUpdated(bool newPauseVault);
    event IbAssetUpdated(address indexed newIbAsset);
    event RewardUpdated(address indexed newReward);
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Profited(uint256 amount);
    event IncentiveClaimed(uint256 amount);
    event SetRouter(address _router);
    event TransferedShare(uint256 amount);
    event ShareUpdated(address _router);

}
