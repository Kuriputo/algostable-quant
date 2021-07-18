// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface IOracleV2 {
    function consult() external view returns (uint256);
    function update() external;
}
