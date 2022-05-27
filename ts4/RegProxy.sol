pragma ton-solidity >= 0.35.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "../DidRegistry.sol";

contract RegProxy {
    DidRegistry public registry;
    address[] public lastDocs;

    constructor(DidRegistry reg) public 
    {
        tvm.accept();
        registry = reg;
    }
    
    function getDidDocs(uint256 pk, address addr)
        external
        returns (address[] docs) 
    {
        tvm.accept();
        registry.getDidDocs{callback: onGetDidDocs, value: 0.1 ton}(pk, addr);
    }

    function onGetDidDocs(address[] docs)
        public
    {
        lastDocs = docs;
    }
}