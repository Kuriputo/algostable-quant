// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IShare.sol";
import "./interfaces/IDollar.sol";


contract ZapPool is Ownable, ReentrancyGuard, Initializable {
    using SafeERC20 for IERC20;
    using Address for address;

    /* ========== STATE VARIABLES ========== */

    IOracle public oracle;
    IDollar public dollar;
    IERC20 public collateral;
    IERC20 public share;
    ITreasury public treasury;

    IUniswapV2Router public router;
    address[] public router_path;
    mapping(address => bool) public whitelistContracts;

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant RATIO_PRECISION = 1e6;
    uint256 private constant COLLATERAL_RATIO_MAX = 1e6;
    uint256 private constant SLIPPAGE_MAX = 100000; // 10%
    uint256 private constant LIMIT_SWAP_TIME = 10 minutes;
    uint256 public slippage = 50000;
    // AccessControl state variables
    bool public mint_paused = false;
    bool public mint_update_oracle = true;

    modifier onlyUserOrWhitelistedContracts() {
        require(!msg.sender.isContract() || whitelistContracts[msg.sender], "Allow non-contract only");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        ITreasury _treasury,
        IDollar _dollar,
        IERC20 _share,
        IERC20 _collateral,
        IOracle _oracleCollateral
    ) external initializer onlyOwner {
        treasury = _treasury;
        dollar = _dollar;
        share = _share;
        collateral = _collateral;
        oracle = _oracleCollateral;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function collateralReserve() public view returns (address) {
        return treasury.collateralReserve();
    }

    function getCollateralPrice() public view returns (uint256) {
        return oracle.consult();
    }

    function unclaimed_pool_collateral() public pure returns (uint256) {
        return 0; // to avoid treasury call exception
    }

    function zapMint(uint256 _collateral_amount, uint256 _dollar_out_min) external onlyUserOrWhitelistedContracts nonReentrant {
        require(mint_paused == false, "Minting is paused");
        if (mint_update_oracle) {
            ITreasury(treasury).updateOracleShare();
        }
        (, uint256 _share_price, , uint256 _tcr, , , uint256 _minting_fee, ) = ITreasury(treasury).info();
        require(_share_price > 0, "Invalid share price");
        uint256 _price_collateral = getCollateralPrice();

        uint256 _collateral_value = (_collateral_amount * _price_collateral) / PRICE_PRECISION;
        uint256 _actual_dollar_amount = _collateral_value - ((_collateral_value * _minting_fee) / PRICE_PRECISION);
        require(_actual_dollar_amount >= _dollar_out_min, "slippage");

        collateral.safeTransferFrom(msg.sender, address(this), _collateral_amount);
        if (_tcr < COLLATERAL_RATIO_MAX) {
            uint256 _share_value = (_collateral_value * (RATIO_PRECISION - _tcr)) / RATIO_PRECISION;
            uint256 _min_share_amount = (_share_value * PRICE_PRECISION * (RATIO_PRECISION - slippage)) / _share_price / RATIO_PRECISION;
            uint256 _swap_collateral_amount = (_collateral_amount * (RATIO_PRECISION - _tcr)) / RATIO_PRECISION;
            collateral.safeApprove(address(router), 0);
            collateral.safeApprove(address(router), _swap_collateral_amount);
            // swap collateral to share
            uint256[] memory _received_amounts = router.swapExactTokensForTokens(_swap_collateral_amount, _min_share_amount, router_path, address(this), block.timestamp + LIMIT_SWAP_TIME);
            emit ZapSwapped(_swap_collateral_amount, _received_amounts[_received_amounts.length - 1]);
        }

        uint256 _balanceShare = IERC20(address(share)).balanceOf(address(this));
        uint256 _balanceCollateral = collateral.balanceOf(address(this));
        if (_balanceShare > 0) {
            _transferShareToReserve(_balanceShare);
        }
        if (_balanceCollateral > 0) {
            _transferCollateralToReserve(_balanceCollateral); // transfer all collateral to reserve no matter what;
        }
        dollar.poolMint(msg.sender, _actual_dollar_amount);
        ITreasury(treasury).updateCollateralMintProfit(_balanceCollateral);
    }

    function _transferCollateralToReserve(uint256 _amount) internal {
        address _reserve = collateralReserve();
        require(_reserve != address(0), "Invalid reserve address");
        collateral.safeTransfer(_reserve, _amount);
        emit TransferedCollateral(_amount);
    }

    function _transferShareToReserve(uint256 _amount) internal {
        address _reserve = collateralReserve();
        require(_reserve != address(0), "Invalid reserve address");
        share.safeTransfer(_reserve, _amount);
        emit TransferedShare(_amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setMintUpdateOracle(bool _mint_update_oracle) external onlyOwner {
        mint_update_oracle = _mint_update_oracle;
    }

    function addWhitelistContract(address _contract) external onlyOwner {
        require(_contract != address(0), "Invalid address");
        require(!whitelistContracts[_contract], "Contract was whitelisted");
        whitelistContracts[_contract] = true;
    }

    function removeWhitelistContract(address _contract) external onlyOwner {
        require(whitelistContracts[_contract], "Contract was not whitelisted");
        delete whitelistContracts[_contract];
    }

    function toggleMinting() external onlyOwner {
        mint_paused = !mint_paused;
    }

    function setSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage <= SLIPPAGE_MAX, "SLIPPAGE TOO HIGH");
        slippage = _slippage;
    }

    function setTreasury(ITreasury _treasury) external onlyOwner {
        require(address(_treasury) != address(0), "Invalid address");
        treasury = _treasury;
    }

    function setOracle(IOracle _oracle) external onlyOwner {
        require(address(_oracle) != address(0), "Invalid address");
        oracle = _oracle;
    }

    function setRouter(address _router, address[] calldata _path) external onlyOwner {
        require(_router != address(0), "Invalid router");
        router = IUniswapV2Router(_router);
        router_path = _path;
    }

    event TransferedCollateral(uint256 indexed collateralAmount);
    event TransferedShare(uint256 indexed shareAmount);
    event ZapSwapped(uint256 indexed collateralAmount, uint256 indexed shareAmount);
}
