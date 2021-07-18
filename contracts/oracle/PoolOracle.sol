// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IPairOracleV2.sol";
import "../interfaces/IMetaSwap.sol";

contract PoolOracle is Ownable, IPairOracleV2 {
    using SafeMath for uint256;

    address public immutable override token0;
    address public immutable override token1;
    IMetaSwap public metaSwap;

    //uint256 public missingDecimals;
    uint256 private constant PRICE_PRECISION = 1e6;

    constructor(address _metaSwap) {
        metaSwap = IMetaSwap(_metaSwap);
        token0 = address(metaSwap.getToken(0));
        token1 = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    }

    // Note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint256 amountIn)
        external
        view
        override
        returns (uint256 amountOut)
    {
        if (token == token0) {
            amountOut = metaSwap.calculateSwapUnderlying(0, 1, amountIn);
        } else {
            require(token == token1, "PoolOracle: INVALID_TOKEN");
            amountOut = metaSwap.calculateSwapUnderlying(1, 0, amountIn);
        }
    }
}
