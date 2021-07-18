// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakeQuantToken is ERC20 {
  constructor(address _reserve) public ERC20('Quant Staker', 'QUANTST') {
     _mint(_reserve, 10e18);
  }
}
