// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

interface IPairOracle {
    function consult(address token, uint256 amountIn) external view returns (uint256 amountOut);

    function update() external;

    function token0() external view returns (address);

    function token1() external view returns (address);
}
