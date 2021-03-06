// SPDX-License-Identifier: Apache-2.0

import "./Tranche.sol";
import "./assets/YC.sol";
import "./interfaces/IElf.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IYCFactory.sol";
import "./interfaces/IYC.sol";

pragma solidity ^0.8.0;

contract TrancheFactory {
    event TrancheCreated(address indexed tracheAddress);

    IYCFactory internal ycFactory;
    address internal tempElfAddress;
    uint256 internal tempExpiration;
    IYC internal tempYC;

    constructor(address _ycFactory) {
        ycFactory = IYCFactory(_ycFactory);
    }

    function deployTranche(uint256 expiration, address elfAddress)
        public
        returns (Tranche tranche)
    {
        tempElfAddress = elfAddress;
        tempExpiration = expiration;

        IElf elfContract = IElf(elfAddress);
        bytes32 salt = keccak256(abi.encodePacked(elfAddress, expiration));
        string memory elfSymbol = elfContract.symbol();
        IERC20 localUnderlying = elfContract.token();
        uint8 localUnderlyingDecimals = localUnderlying.decimals();

        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(type(Tranche).creationCode)
                        )
                    )
                )
            )
        );

        tempYC = ycFactory.deployYc(
            predictedAddress,
            elfSymbol,
            expiration,
            localUnderlyingDecimals
        );

        Tranche tranche = new Tranche{ salt: salt }();
        emit TrancheCreated(address(tranche));

        // set back to 0-value for some gas savings
        delete tempElfAddress;
        delete tempExpiration;
        delete tempYC;

        return tranche;
    }

    function getData()
        external
        returns (
            address,
            uint256,
            IYC
        )
    {
        return (tempElfAddress, tempExpiration, tempYC);
    }
}
