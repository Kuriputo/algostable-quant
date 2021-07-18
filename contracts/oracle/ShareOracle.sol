// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

import "../interfaces/IOracle.sol";
import "../interfaces/IPairOracle.sol";

contract ShareOracle is Ownable, IOracle {
    using SafeMath for uint256;
    address public oracleShareBusd;
    address public chainlinkBusdUsd;
    address public share;

    uint256 private constant PRICE_PRECISION = 1e6;

    constructor(
        address _share,
        address _oracleShareBusd,
        address _chainlinkBusdUsd
    ) public {
        share = _share;
        chainlinkBusdUsd = _chainlinkBusdUsd;
        oracleShareBusd = _oracleShareBusd;
    }

    function consult() external view override returns (uint256) {
        uint256 _priceBusdUsd = priceBusdUsd();
        uint256 _priceShareBusd = IPairOracle(oracleShareBusd).consult(share, PRICE_PRECISION);
        return _priceBusdUsd.mul(_priceShareBusd).div(PRICE_PRECISION);
    }

    function update() external {
        IPairOracle(oracleShareBusd).update();
    }

    function priceBusdUsd() internal view returns (uint256) {
        AggregatorV3Interface _priceFeed = AggregatorV3Interface(chainlinkBusdUsd);
        (, int256 _price, , , ) = _priceFeed.latestRoundData();
        uint8 _decimals = _priceFeed.decimals();
        return uint256(_price).mul(PRICE_PRECISION).div(uint256(10)**_decimals);
    }

    function setChainlinkBusdUsd(address _chainlinkBusdUsd) external onlyOwner {
        chainlinkBusdUsd = _chainlinkBusdUsd;
    }

    function setOracleShareBusd(address _oracleShareBusd) external onlyOwner {
        oracleShareBusd = _oracleShareBusd;
    }
}
