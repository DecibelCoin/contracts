// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract DecibelCoin is ERC20, ERC20Burnable, AccessControl {
  using SafeMath for uint256;
  using Address for address;

  bytes32 public constant MINTER_ROLE = keccak256("MINTER");

  constructor() ERC20("DecibelCoin", "DBC") {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);
  }

  modifier onlyMinters() {
    require(isMinter(msg.sender), "Restricted to minters.");
    _;
  }

  function isMinter(address addr) public view returns (bool) {
    return hasRole(MINTER_ROLE, addr);
  }

  function addMinter(address addr) public onlyRole(DEFAULT_ADMIN_ROLE) {
    grantRole(MINTER_ROLE, addr);
  }

  function mint(address to, uint256 amount) public onlyMinters {
    _mint(to, amount);
  }
}
