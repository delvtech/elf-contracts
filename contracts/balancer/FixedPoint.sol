/* cSpell:disable */
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

pragma solidity >=0.7.1;

/* solhint-disable private-vars-leading-underscore */

library FixedPoint {
    uint128 internal constant ONE = 10**18; // 18 decimal places

    uint256 internal constant MIN_POW_BASE = 1 wei;
    uint256 internal constant MAX_POW_BASE = (2 * ONE) - 1 wei;
    uint256 internal constant POW_PRECISION = ONE / 10**10;

    function btoi(uint256 a) internal pure returns (uint256) {
        return a / ONE;
    }

    function floor(uint256 a) internal pure returns (uint256) {
        return btoi(a) * ONE;
    }

    function abs(int256 a) internal pure returns (uint256) {
        if (a > 0) {
            return uint256(a);
        } else {
            return uint256(-a);
        }
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    function add128(uint128 a, uint128 b) internal pure returns (uint128) {
        uint128 c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        (uint256 c, bool flag) = subSign(a, b);
        require(!flag, "ERR_SUB_UNDERFLOW");
        return c;
    }

    function subSign(uint256 a, uint256 b)
        internal
        pure
        returns (uint256, bool)
    {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    function sub128(uint128 a, uint128 b) internal pure returns (uint128) {
        (uint128 c, bool flag) = subSign128(a, b);
        require(!flag, "ERR_SUB_UNDERFLOW");
        return c;
    }

    function subSign128(uint128 a, uint128 b)
        internal
        pure
        returns (uint128, bool)
    {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint256 c1 = c0 + (ONE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint256 c2 = c1 / ONE;
        return c2;
    }

    function mul128(uint128 a, uint128 b) internal pure returns (uint128) {
        uint128 c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint128 c1 = c0 + (ONE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint128 c2 = c1 / ONE;
        return c2;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * ONE;
        require(a == 0 || c0 / a == ONE, "ERR_DIV_INTERNAL"); // mul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  add require
        uint256 c2 = c1 / b;
        return c2;
    }

    function div128(uint128 a, uint128 b) internal pure returns (uint128) {
        require(b != 0, "ERR_DIV_ZERO");
        uint128 c0 = a * ONE;
        require(a == 0 || c0 / a == ONE, "ERR_DIV_INTERNAL"); // mul overflow
        uint128 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  add require
        uint128 c2 = c1 / b;
        return c2;
    }

    // DSMath.wpow
    function powi(uint256 a, uint256 n) internal pure returns (uint256) {
        uint256 z = n % 2 != 0 ? a : ONE;

        for (n /= 2; n != 0; n /= 2) {
            a = mul(a, a);

            if (n % 2 != 0) {
                z = mul(z, a);
            }
        }
        return z;
    }

    // credit for this implementation goes to
    // https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol#L687
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        // this block is equivalent to r = uint256(1) << (BitMath.mostSignificantBit(x) / 2);
        // however that code costs significantly more gas
        uint256 xx = x;
        uint256 r = 1;
        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x8) {
            r <<= 1;
        }
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }
}
