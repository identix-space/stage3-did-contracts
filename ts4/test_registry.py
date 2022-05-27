from collections import defaultdict, namedtuple
from http.client import NO_CONTENT
from sys import flags
import urllib.request as ur
import os 
import tonos_ts4.ts4 as ts4
from tonos_ts4.address import Address
from tonos_ts4.global_functions import zero_addr

eq = ts4.eq
ton = ts4.GRAM

class DidContractError:
    MessageSenderIsNotOwner = 200
    MessageSenderIsNeitherOwnerNorAuthority = 201
    MissingOwnerPublicKeyOrAddressOrBothGiven = 202
    MissingOwnerPublicKey = 203
    MissingIssuerAddress = 204
    ValueTooLow = 205

# Initialize TS4 by specifying where the artifacts of the used contracts are located
# verbose: toggle to print additional execution info
ts4.init('../', verbose = False)

KeyPair = namedtuple('KeyPair', 'private public')


def check_method_params(abi, method, params):
    assert isinstance(abi, ts4.Abi)

    if method == '.data':
        inputs = abi.json['data']
    else:
        func = abi.find_abi_method(method)
        if func is None:
            raise Exception("Unknown method name '{}'".format(method))
        inputs = func['inputs']
    res = {}
    for param in inputs:
        pname = param['name']
        if pname not in params:
            # THIS IS WHAY THIS WORKABOUTN ABOUT
            if pname == 'answerId':
                params['answerId'] = 0
            else:
            # ENDOF WORKAROUND
                raise Exception("Parameter '{}' is missing when calling method '{}'".format(pname, method))
        res[pname] = ts4.check_param_names_rec(params[pname], ts4.AbiType(param))
    return res

ts4.check_method_params = check_method_params

reg_owner = KeyPair(*ts4.make_keypair())
doc_owner1 = KeyPair(*ts4.make_keypair())
unauthorized = KeyPair(*ts4.make_keypair())

DID_DOC_CONTENTS = 'This is the text'
DID_DOC_CONTENTS2 = 'This is the text too'

# deploying wallets
WALLET_CONTRACT = 'SafeMultisigWallet'
if not os.path.exists(WALLET_CONTRACT + '.abi.json'):
    ur.urlretrieve(f'https://raw.githubusercontent.com/tonlabs/ton-labs-contracts/5ee039e4d093b91b6fdf7d77b9627e2e7d37f000/solidity/safemultisig/{WALLET_CONTRACT}.tvc', f'./{WALLET_CONTRACT}.tvc')
    ur.urlretrieve(f'https://raw.githubusercontent.com/tonlabs/ton-labs-contracts/5ee039e4d093b91b6fdf7d77b9627e2e7d37f000/solidity/safemultisig/{WALLET_CONTRACT}.abi.json', f'./{WALLET_CONTRACT}.abi.json')

reg_owner_wallet = ts4.BaseContract(WALLET_CONTRACT, dict(owners = [reg_owner.public], reqConfirms = 0), keypair=reg_owner, balance=50*ton)
doc_owner_wallet = ts4.BaseContract(WALLET_CONTRACT, dict(owners = [doc_owner1.public], reqConfirms = 0), keypair=doc_owner1, balance=5*ton)
unauthorized_wallet = ts4.BaseContract(WALLET_CONTRACT, dict(owners = [unauthorized.public], reqConfirms = 0), balance=5*ton)

registry = ts4.BaseContract('DidRegistry', dict(controllerPubKey_ = 0, controllerAddress_ = reg_owner_wallet.address), balance=2*ton, keypair=reg_owner, nickname='Registry')

reg_proxy = ts4.BaseContract('ts4/RegProxy', dict(reg = registry.address), balance=10*ton)

def test_set_template():
    params = dict(code = ts4.load_code_cell('DidDocument'))
    registry.call_method('setTemplate', params, expect_ec=DidContractError.MessageSenderIsNeitherOwnerNorAuthority)
    registry.call_method('setTemplate', params, private_key=unauthorized.private, expect_ec=DidContractError.MessageSenderIsNeitherOwnerNorAuthority)
    reg_wallet_call('setTemplate', params, value=0.5*ton)


def test_issueDoc():
    doc_addr = issue_doc(DID_DOC_CONTENTS, doc_owner1.public, value=3*ton)
    doc = ts4.BaseContract('DidDocument', {}, address=doc_addr)
    
    assert eq(f'did:ever:{doc_addr.str()[2:]}', doc.call_method_signed('getDid', dict()))
    assert eq(DID_DOC_CONTENTS, doc.call_method('getContent', dict(representationType = 0))  )
    assert eq_pk(doc.call_getter('getOwner', dict())[0], doc_owner1.public)
    assert eq(doc.call_getter('getOwner', dict())[1], Address.zero_addr())

    doc.call_method('setContent', dict(content = DID_DOC_CONTENTS2, representationType = 0), private_key=doc_owner1.private)
    assert eq(DID_DOC_CONTENTS2, doc.call_method('getContent', dict(representationType = 0)))

    doc.call_method('setContent', dict(content = DID_DOC_CONTENTS2, representationType = 0), private_key=unauthorized.private, expect_ec=DidContractError.MessageSenderIsNeitherOwnerNorAuthority)


def test_different_docs():
    doc1 = issue_doc(DID_DOC_CONTENTS, doc_owner1.public, value=1.5*ton)
    doc2 = issue_doc(DID_DOC_CONTENTS, doc_owner1.public, value=1.5*ton)
    assert doc1 != doc2


def test_issueDoc_gas():
    initial_balance = registry.balance
    doc_addr = issue_doc(DID_DOC_CONTENTS, doc_owner1.public, value=1.5*ton)
    aftermatch_balance = registry.balance
    #registry.ensure_balance(initial_balance)


def test_change_doc_owner():
    doc_addr = issue_doc(DID_DOC_CONTENTS, doc_owner1.public, value=3*ton)
    doc = ts4.BaseContract('DidDocument', {}, keypair=doc_owner1, address=doc_addr)
    doc.call_method('changeOwner', dict(eitherNewOwnerPubKey=0, orNewOwnerAddress=Address.zero_addr()), expect_ec=DidContractError.MessageSenderIsNotOwner)
    doc.call_method_signed('changeOwner', dict(eitherNewOwnerPubKey=0, orNewOwnerAddress=Address.zero_addr()), expect_ec=DidContractError.MissingOwnerPublicKeyOrAddressOrBothGiven)

    doc.call_method_signed('changeOwner', dict(eitherNewOwnerPubKey=unauthorized.public, orNewOwnerAddress=Address.zero_addr()))
    (doc.private_key_, doc.public_key_) = unauthorized
    assert eq_pk(doc.call_getter('getOwner', dict())[0], unauthorized.public)
    assert eq(doc.call_getter('getOwner', dict())[1], Address.zero_addr())

    doc.call_method_signed('changeOwner', dict(eitherNewOwnerPubKey=0, orNewOwnerAddress=reg_owner_wallet.address))
    (doc.private_key_, doc.public_key_) = (None, None)
    assert eq_pk(doc.call_getter('getOwner', dict())[0], 0)
    assert eq(doc.call_getter('getOwner', dict())[1], reg_owner_wallet.address)


def test_change_registry_owner():
    registry.call_method('changeOwner', dict(eitherNewOwnerPubKey=0, orNewOwnerAddress=Address.zero_addr()), expect_ec=DidContractError.MessageSenderIsNotOwner)
    reg_wallet_call('changeOwner', dict(eitherNewOwnerPubKey=0, orNewOwnerAddress=Address.zero_addr()), value=0.1*ton, expect_ec=DidContractError.MissingOwnerPublicKeyOrAddressOrBothGiven)
    
    reg_wallet_call('changeOwner', dict(eitherNewOwnerPubKey=unauthorized.public, orNewOwnerAddress=Address.zero_addr()), value=0.1*ton)
    (registry.private_key_, registry.public_key_) = unauthorized
    assert eq(registry.g.controllerAddress(), Address.zero_addr())
    assert eq_pk(registry.g.controllerPubKey(), unauthorized.public)

    registry.call_method_signed('changeOwner', dict(eitherNewOwnerPubKey=0, orNewOwnerAddress=reg_owner_wallet.address))
    (registry.private_key_, registry.public_key_) = reg_owner_wallet.keypair
    assert eq(registry.g.controllerAddress(), reg_owner_wallet.address)
    assert eq_pk(registry.g.controllerPubKey(), 0)


def test_reset_doc_storage():
    reg_wallet_call('resetDocStorage', {}, value=0.1*ton)
    issue_doc(DID_DOC_CONTENTS, ownerAddress=reg_owner_wallet.address, value=1.5*ton)
    issue_doc(DID_DOC_CONTENTS, ownerAddress=reg_owner_wallet.address, value=1.5*ton)
    issue_doc(DID_DOC_CONTENTS, ownerAddress=reg_owner_wallet.address, value=1.5*ton)
    assert len(get_docs(ownerAddr=reg_owner_wallet.address)) == 3
    reg_wallet_call('resetDocStorage', {}, value=0.1*ton)
    assert len(get_docs(ownerAddr=reg_owner_wallet.address)) == 0
    


###### utils ######
def issue_doc(content: str, ownerPubKey: int=0, ownerAddress: Address=Address.zero_addr(), value: int=0) -> Address:
    params = dict(docOwnerPubKey=ownerPubKey, docOwnerAddress=ownerAddress, content=content, initialDocBalance=int(0.5*ton))
    reg_wallet_call('issueDidDoc', params, value=value)
    ts4.dispatch_messages()
    docs = get_docs(ownerPk=ownerPubKey, ownerAddr=ownerAddress)
    doc_addr = docs[-1]
    Address.ensure_address(doc_addr)
    return doc_addr


def reset_doc_storage():
    reg_wallet_call('reset_doc_storage', {}, value=0.1*ton)


def reg_wallet_call(method: str, call_args: dict, value: int = 0, expect_ec=0):
    call_args['answerId'] = 0
    body = ts4.encode_message_body('DidRegistry', method, call_args)
    txId = reg_owner_wallet.call_method_signed( \
        'sendTransaction', \
        dict(dest = registry.address, value = int(value), bounce = False, flags = 0, payload = body))
    ts4.dispatch_one_message(expect_ec)


def get_docs(ownerPk: int = 0, ownerAddr: Address = Address.zero_addr()) -> Address:
    d = reg_proxy.call_method_signed('getDidDocs', dict(pk=ownerPk, addr=ownerAddr))
    ts4.dispatch_one_message()
    ts4.dispatch_one_message()
    return reg_proxy.g.lastDocs()


def eq_pk(pk1, pk2) -> bool:
    if isinstance(pk1, int):
        pk1 = f'0x{pk1:x}'
    if isinstance(pk2, int):
        pk2 = f'0x{pk2:x}'
    return eq(pk1, pk2)
###### main test calls ######

test_set_template()
test_issueDoc()
test_different_docs()
test_issueDoc_gas()
test_change_registry_owner()
test_change_doc_owner()
test_reset_doc_storage()
# Ensure we have no undispatched messages
ts4.ensure_queue_empty()

