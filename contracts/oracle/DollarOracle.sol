// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IPairOracleV2.sol";

contract DollarOracle is Ownable, IOracle {
    address public oracleDollarCollateral;
    address public oracleCollateralUsd;
    address public dollar;

    //uint256 public missingDecimals;
    uint256 private constant PRICE_PRECISION = 1e6;

    constructor(
        address _dollar,
        address _oracleDollarCollateral,
        address _oracleCollateralUsd
    ) {
        dollar = _dollar;
        oracleCollateralUsd = _oracleCollateralUsd;
        oracleDollarCollateral = _oracleDollarCollateral;
    }

    function consult() external view override returns (uint256) {
        uint256 _priceCollateralUsd = IOracle(oracleCollateralUsd).consult();
        uint256 _priceDollarCollateral =
            IPairOracleV2(oracleDollarCollateral).consult(
                dollar,
                PRICE_PRECISION
            );
        return (_priceCollateralUsd * _priceDollarCollateral) / PRICE_PRECISION;
    }

    /* function update() external {
        IPairOracle(oracleDollarCollateral).update();
    } */

    function setOracleCollateralUsd(address _oracleCollateralUsd) external onlyOwner {
        oracleCollateralUsd = _oracleCollateralUsd;
    }

    function setOracleDollarCollateral(address _oracleDollarCollateral) external onlyOwner {
        oracleDollarCollateral = _oracleDollarCollateral;
    }
}
