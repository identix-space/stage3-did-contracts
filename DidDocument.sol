pragma ton-solidity >= 0.35.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "./DidContractErrors.sol";
import "./Utils.sol";
import "./DidInterfaces.sol";


contract DidDocument is IDidDocument  {

    // https://www.w3.org/TR/did-core/#representations
    // media type => representation. "json" by default
    // TODO: shall be string => bytes to generalize representation content type
    mapping (uint8 => string) public representations;
    uint256 ownerPubKey;
    address ownerAddress;
    bool isActive;
    address static issuingAuthority;

    constructor(uint256 ownerPubKey_, address ownerAddress_) public 
    {
        require(Utils.isPubKeyXorAddressNotEmpty(ownerPubKey_, ownerAddress_), DidContractError.MissingOwnerPublicKeyOrAddressOrBothGiven);
        require(msg.sender.value != 0, DidContractError.MissingIssuerAddress);
        tvm.accept();
        ownerPubKey = ownerPubKey_;
        ownerAddress = ownerAddress_;
        isActive = true;
    }

    ////// IDidDocument impl /////

    function getOwner() 
        override
        external view responsible 
        returns (uint256 pubKey, address addr)
    {
        tvm.accept();
        return (ownerPubKey, ownerAddress);
    }

    function getDid()
        override
        external view responsible 
        returns (string did)
    {
        tvm.accept();
        // Currently, DID method scheme is not configured
        // https://www.w3.org/TR/did-core/#did-syntax
        return format("did:ever:{:064x}", address(this).value);
    }

    function setContent(string content, uint8 representationType) 
        override
        external
        checkAccessAndAccept()
    {
        tvm.accept();
        representations[MimeDidType.JSON] = content;
    }

    function getContent(uint8 representationType) 
        override
        external view responsible
        returns (string) 
    {
        tvm.accept();
        return representations[MimeDidType.JSON];
    }

    function getActive()
        override
        external view responsible
        returns (bool)
    {
        return isActive;
    }

    function setActive(bool newValue)
        override
        external
        checkAccessAndAccept()
    {
        isActive = newValue;
    }

    function changeOwner(uint256 eitherNewOwnerPubKey, address orNewOwnerAddress)
        override
        external
    {
        require(isOwner(), DidContractError.MessageSenderIsNotOwner);
        require(Utils.isPubKeyXorAddressNotEmpty(eitherNewOwnerPubKey, orNewOwnerAddress), DidContractError.MissingOwnerPublicKeyOrAddressOrBothGiven);
        tvm.accept();
        ownerPubKey = eitherNewOwnerPubKey;
        ownerAddress = orNewOwnerAddress;
    }

    ////// Access //////
    
    modifier checkAccessAndAccept()
    {
        require(isOwner() || isAuthority(), DidContractError.MessageSenderIsNeitherOwnerNorAuthority);
        tvm.accept();
        _;
    }

    function isOwner() private view inline returns (bool)
    {
        return ownerPubKey == msg.pubkey() && ownerAddress.value == 0 
            || ownerPubKey == 0 && ownerAddress == msg.sender;
    }

    function isAuthority() private view inline returns (bool)
    {
        return msg.sender == issuingAuthority;
    }

    ////// General //////
    function transfer(address dest, uint128 amount, bool bounce) 
        public pure
    {
        dest.transfer(amount, bounce, 0);
    }
}
