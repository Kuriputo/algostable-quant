// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./StakeQuantToken.sol";
import "./interfaces/ICollateralReserve.sol";
import "./interfaces/IFairLaunchQuant.sol";

contract CollateralReserve is Ownable, ICollateralReserve, Initializable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // CONTRACTS
    address public treasury;
    bool public initFairlunch;
    IFairLaunchQuant public fairLaunch;
    uint256 public pid;
    address public quant;
    StakeQuantToken public stakeQuantToken;

    /* ========== MODIFIER ========== */

    modifier onlyTreasury() {
        require(treasury == msg.sender, "Only treasury can trigger this function");
        _;
    }

    function initialize(address _treasury, address _fairLaunch, address _quant) external onlyOwner initializer {
        require(_treasury != address(0), "Invalid address");
        require(_fairLaunch != address(0), "Invalid address");
        treasury = _treasury;
        fairLaunch = IFairLaunchQuant(_fairLaunch);
        quant = _quant;
        stakeQuantToken = new StakeQuantToken(address(this));
    }

    /* ========== VIEWS ================ */

    function fundBalance(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function transferTo(
        address _token,
        address _receiver,
        uint256 _amount
    ) public override onlyTreasury {
        require(_receiver != address(0), "Invalid address");
        require(_amount > 0, "Cannot transfer zero amount");
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "Invalid address");
        treasury = _treasury;
        emit TreasuryChanged(treasury);
    }

    function initialFairlunchQuant(uint256 _pid) public onlyOwner{
        require(!initFairlunch, "Already Initiated");
        IERC20(address(stakeQuantToken)).safeApprove(address(fairLaunch), 0);
        IERC20(address(stakeQuantToken)).safeApprove(address(fairLaunch), uint256(1e18));
        pid = _pid;
        initFairlunch = true;
        fairLaunch.deposit(pid, 1e18);
        emit InitFairLunch(pid, 1e18);
    }

    function harvest() public {
        _harvest();
    }

    function _harvest() internal {

      uint256 amountBefore = IERC20(quant).balanceOf(address(this));
      fairLaunch.harvest(pid);
      uint256 amountAfter = IERC20(quant).balanceOf(address(this)).sub(amountBefore);

      emit Harvest(amountAfter);
    }


    event TreasuryChanged(address indexed newTreasury);
    event Harvest(uint256 amount);
    event InitFairLunch(uint256 pid, uint256 amount);

}
