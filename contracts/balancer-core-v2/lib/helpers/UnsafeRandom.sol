// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library UnsafeRandom {
    function rand(uint256 mod) internal view returns (uint256) {
        uint256 previousBlockNumber = block.number - 1;
        bytes32 seed = blockhash(previousBlockNumber);
        return uint256(seed) % mod;
    }

    function rand(IERC20[] memory list) internal view returns (IERC20, uint256) {
        uint256 randomIndex = rand(list.length);
        return (list[randomIndex], randomIndex);
    }
}
