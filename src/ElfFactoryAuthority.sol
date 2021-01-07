pragma solidity >=0.5.8 <0.8.0;

contract ElfFactoryAuthority {

    bool internal _initialized = false;
    address internal _elfFactory;

    function initialize(address elfFactory) public {
        require(elfFactory != address(0), "elfFactory must be a valid address");
        require(! _initialized, "elfFactory already initialized");

        _elfFactory = elfFactory;
        _initialized = true;
    }

    modifier onlyFactory(){
        require(_initialized, "Factory initialization must have been called.");
        require(msg.sender == _elfFactory, "Caller must be depositFactory contract");
        _;
    }
}