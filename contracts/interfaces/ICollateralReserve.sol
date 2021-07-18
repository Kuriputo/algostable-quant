// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface ICollateralReserve {
    function transferTo(
        address _token,
        address _receiver,
        uint256 _amount
    ) external;
}
