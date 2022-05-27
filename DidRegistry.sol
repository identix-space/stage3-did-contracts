pragma ton-solidity >= 0.35.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "DidContractErrors.sol";
import "Gas.sol";
import "DidDocument.sol";
import "Utils.sol";

contract DidRegistry {

    TvmCell private templateCode;
    uint256 public controllerPubKey;
    address public controllerAddress;
    mapping (address => address[]) private documentsByAddress;
    mapping (uint256 => address[]) private documentsByPubKey;
    uint8 private ver = 1;

    constructor(uint256 controllerPubKey_, address controllerAddress_) 
        public
    {
        require(Utils.isPubKeyXorAddressNotEmpty(controllerPubKey_, controllerAddress_), DidContractError.MissingOwnerPublicKeyOrAddressOrBothGiven);
        tvm.accept();
        if (controllerAddress_.value != 0)
        {
            controllerAddress = controllerAddress_;
        }
        else // if (controllerPubKey_ != 0)
        {
            controllerPubKey = controllerPubKey_;
        }
    }

    ////// Document management //////

    // Currently, only application/did+json MIME type
    // None of docOwnerPubKey and docOwnerAddress must be null in the same time
    function issueDidDoc(uint256 docOwnerPubKey, address docOwnerAddress, string content, uint32 initialDocBalance) 
        external responsible
        checkAccessAndAccept
        returns (address didDocAddr) 
    {
        require(Utils.isPubKeyXorAddressNotEmpty(docOwnerPubKey, docOwnerAddress), DidContractError.MissingOwnerPublicKeyOrAddressOrBothGiven);

        uint128 expectedValue = Gas.RegistryFeeOnIssuingDoc + Gas.DeployDocInitialValue;
        tvm.accept();

        TvmBuilder salt;
        salt.store(tx.timestamp);
        TvmCell saltedCode = tvm.setCodeSalt(templateCode, salt.toCell());

		TvmCell stateInit = tvm.buildStateInit(
        {
            contr: DidDocument,
            code: saltedCode,
            pubkey: docOwnerPubKey,
            varInit: 
            {
                issuingAuthority: address(this)
            }
        });

		address addr = new DidDocument
        {
            stateInit: stateInit, 
            value: initialDocBalance
        }
        (docOwnerPubKey, docOwnerAddress);

        IDidDocument(addr).setContent(content, 0);

        if (docOwnerPubKey != 1)
            documentsByPubKey[docOwnerPubKey].push(addr);
        if (docOwnerAddress != address(0))
            documentsByAddress[docOwnerAddress].push(addr);
        
        return (addr);
    }

    // now no access control is implemented
    function getDidDocs(uint256 eitherDocOwnerPubKey, address orDocOwnerAddress)
        external responsible
        returns (address[] docs) 
    {
        require(Utils.isPubKeyXorAddressNotEmpty(eitherDocOwnerPubKey, orDocOwnerAddress), DidContractError.MissingOwnerPublicKeyOrAddressOrBothGiven);
        address[] result;
        if (eitherDocOwnerPubKey != 0)
            result = documentsByPubKey[eitherDocOwnerPubKey];
        else if (orDocOwnerAddress != address(0))
            result = documentsByAddress[orDocOwnerAddress];
        return result;
    }

    function resetDocStorage()
        public
        checkAccessAndAccept
    {
        delete documentsByAddress;
        delete documentsByPubKey;
    }

    ////// Templating //////
    function setTemplate(TvmCell code) 
        external
        checkAccessAndAccept()
    {
        templateCode = code;
    }

    ////// Access //////
    
    modifier checkAccessAndAccept() 
    {
        require(isOwner(), DidContractError.MessageSenderIsNeitherOwnerNorAuthority);
        tvm.accept();
        _;
    }

    function isOwner()
        private view
        returns (bool)
    {
        return controllerPubKey == msg.pubkey() && controllerAddress.value == 0 
            || controllerPubKey == 0 && controllerAddress == msg.sender;
    }

    function changeOwner(uint256 eitherNewOwnerPubKey, address orNewOwnerAddress)
        external
    {
        require(isOwner(), DidContractError.MessageSenderIsNotOwner);
        require(Utils.isPubKeyXorAddressNotEmpty(eitherNewOwnerPubKey, orNewOwnerAddress), DidContractError.MissingOwnerPublicKeyOrAddressOrBothGiven);
        tvm.accept();
        controllerPubKey = eitherNewOwnerPubKey;
        controllerAddress = orNewOwnerAddress;
    }

    ////// General //////
    function transfer(address dest, uint128 amount, bool bounce) 
        public pure
        checkAccessAndAccept()
    {
        dest.transfer(amount, bounce, 0);
    }
}