// SPDX-License-Identifier: Apache-2.0

import "./Tranche.sol";
import "./assets/YC.sol";
import "./interfaces/IElf.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IYCFactory.sol";
import "./interfaces/IYC.sol";

pragma solidity ^0.8.0;

contract TrancheFactory {
    event TrancheCreated(address indexed trancheAddress);

    IYCFactory internal ycFactory;
    address internal tempElfAddress;
    uint256 internal tempExpiration;
    IYC internal tempYC;

    /// @notice Create a new Tranche.
    /// @param _ycFactory Address of the YC factory.
    constructor(address _ycFactory) {
        ycFactory = IYCFactory(_ycFactory);
    }

    /// @notice Deploy a new Tranche contract.
    /// @param expiration The expiration timestamp for the tranche.
    /// @param elfAddress Address of the Elf contract the tranche will use.
    /// @return The deployed Tranche contract.
    function deployTranche(uint256 expiration, address elfAddress)
        public
        returns (Tranche)
    {
        tempElfAddress = elfAddress;
        tempExpiration = expiration;

        IElf elfContract = IElf(elfAddress);
        bytes32 salt = keccak256(abi.encodePacked(elfAddress, expiration));
        string memory elfSymbol = elfContract.symbol();
        IERC20 underlying = elfContract.token();
        uint8 underlyingDecimals = underlying.decimals();

        // derive the expected tranche address
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
            underlyingDecimals
        );

        Tranche tranche = new Tranche{ salt: salt }();
        emit TrancheCreated(address(tranche));

        require(
            address(tranche) == predictedAddress,
            "CREATE2 address mismatch"
        );

        // set back to 0-value for some gas savings
        delete tempElfAddress;
        delete tempExpiration;
        delete tempYC;

        return tranche;
    }

    /// @notice Callback function called by the Tranche.
    /// @dev This is called by the Tranche contract constructor.
    /// The return data is used for Tranche initialization. Using this, the Tranche avoids
    /// constructor arguments which can make the Tranche bytecode needed for create2 address
    /// derivation non-constant.
    /// @return Elf contract address, expiration timestamp, and YC contract
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
