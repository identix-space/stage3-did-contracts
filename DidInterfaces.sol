pragma ton-solidity >= 0.35.0;

// https://github.com/tonlabs/TON-Solidity-Compiler/blob/master/API.md#tvmrawreserve
library MsgFlag {
    uint8 constant SenderPaysFee        = 1;
    uint8 constant IgnoreErrors         = 2;
    uint8 constant DestoryIfZero        = 32;
    uint8 constant RemainingGas         = 64;
    uint8 constant AllNotReserved       = 128;
}

library MimeDidType {
    // Normative value is 'application/did+json', but let's save a few bits for now...
    uint8 public constant JSON = 1;
    uint8 public constant JSON_LD = 2;
    uint8 public constant CBOR = 3;
}


interface IDidDocument {

    // Owner of DidDocument
    function getOwner() external view responsible returns (uint256 pubKey, address addr);

    // "The DID for a particular DID subject is expressed using the id property in the DID document."
    // https://www.w3.org/TR/did-core/#identifiers
    function getDid() external view responsible returns (string did);

    // "A concrete serialization of a DID document is called a representation."
    // https://www.w3.org/TR/did-spec-registries/#representations
    // DidDocument may have a set of representations of different types: JSON, JSON-LD, CBOR etc.
    // Currently, we implement only 'application/did+json' representation, so the type params is ignored.
    // "When serializing a DID document, a conforming producer MUST specify a media type of application/did+json"
    // https://w3c.github.io/did-core/#production
    function setContent(string content, uint8 representationType) external;

    // returns content of 'application/did+json'
    function getContent(uint8 representationType) external view responsible returns (string);

    function getActive() external view responsible returns (bool);
    function setActive(bool newValue) external;

    function changeOwner(uint256 eitherNewOwnerPubKey, address orNewOwnerAddress) external;
}