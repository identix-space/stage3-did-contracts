pragma ton-solidity >= 0.35.0;

library DidContractError {
    uint8 constant MessageSenderIsNotOwner = 200;
    uint8 constant MessageSenderIsNeitherOwnerNorAuthority = 201;
    uint8 constant MissingOwnerPublicKeyOrAddressOrBothGiven = 202;
    uint8 constant MissingOwnerPublicKey = 203;
    uint8 constant MissingIssuerAddress = 204;
    uint8 constant ValueTooLow = 205;
}