#!/bin/bash
#set -x
. td-tools.sh

initial_balance=5000000000
network=Unknown
do_reset=0
owner_pk=0

for a in $@
do
    if [[ "$owner_pk" = "1" ]]
    then
        owner_pk=$a
    fi
    case $a in
        "se") network=se;;
        "dev") network=dev;;
        "main") network=main;;
        "reset") do_reset=1;;
        "eo") owner_pk=1;;
    esac
done

if [[ "$network" = "dev" ]] 
then
    giver_arg="-v $initial_balance"
    url_param=""
    signer=test122021
    wallet_address=9ca9392294d40fe2fd26eb14eb06735939552cd709b4e3714e3afdc1e955828e
    yell DEV network
elif [[ "$network" = "se" ]] 
then
    giver_arg="-v $initial_balance"
    url_param="-u localhost"
    signer=test122021
    wallet_address=737e2f945277f6536085369385ab6d57a913066b7274a6095bec5d8e8e2f1008
    yell SE network
elif [[ "$network" = "main" ]] 
then
    giver_arg=""
    url_param="-u main.ton.dev"
    signer=test122021
    wallet_address=00c9418e59d2f6aab6bb891b4e2f63733d37d15f41f229ff57ea84d00eae477f
    yell MAIN network
else
    die $network is now valid for target network
fi

if [[ "$network" = "se" ]] && [[ "$do_reset" = "1" ]]; then 
    everdev se reset; 
    wallet_owner_pub_key=$(everdev s l | pcregrep -o1 'test122021\s+([0-9a-z]+)')
    wallet_address=$(everdev c d SafeMultisigWallet -v 10000000000 -i owners:[0x$wallet_owner_pub_key],reqConfirms:0 | grep_deploy_addr)
    yell Created wallet: 0:$wallet_address
else
    yell wallet: 0:$wallet_address
fi


ddcode=$(decode_contract_code DidDocument.tvc)

if [[ "$owner_pk" = "0" ]]
then
    yell Deploying wallet owned registry
    # TEST REGISTRY DEPLOY
    registry_addr=$(deploy_contract DidRegistry $network $signer $giver_arg -i controllerPubKey_:0,controllerAddress_:$wallet_address)
    yell DidRegistry deployed at 0:$registry_addr

    #TEST SET TEMPLATE
    yell "Setting template..."
    body=$(tonos-cli $url_param body --abi DidRegistry.abi.json setTemplate "{\"code\":\"$ddcode\"}" | grep body | cut -d' ' -f3)
    input="dest:\"0:$registry_addr\",value:1000000000,bounce:true,flags:0,payload:\"$body\""
    success=$(everdev contract run -n $network -s $signer -a 0:$wallet_address SafeMultisigWallet sendTransaction --input "$input" | grep_success)
    assert_not_empty "$success" "Cannot set template"
    yell $(f_green OK)
else
    [[ "$owner_pk" = "1" ]] && die Provide external owner public key!
    yell Deploying pubkey owned registry
    registry_addr=$(deploy_contract DidRegistry $network $signer $giver_arg -i controllerPubKey_:0x$owner_pk,controllerAddress_:$zero_addr)
    yell DidRegistry deployed at 0:$registry_addr
    yell "Setting template..."
    success=$(everdev c r -n $network -s $signer DidRegistry setTemplate -i code:$ddcode)
    assert_not_empty "$success" "Cannot set template"
    yell $(f_green OK)
fi

# Test case
## deploy
# ./deploy.sh se eo $(cat ~/tonkeys/test122021 | grep public | cut -d'"' -f4)
## issueDidDoc:
# everdev c r -n se -s test122021 DidRegistry issueDidDoc -i docOwnerPubKey:0x$(cat ~/tonkeys/test122021 | grep public | cut -d'"' -f4),docOwnerAddress:0000000000000000000000000000000000000000000000000000000000000000,content:'11111',initialDocBalance:200000000,answerId:0 | grep didDocAddr | cut -d'"' -f4
# check content
# everdev c r -n se -s test122021 -a <ADDR> DidDocument getContent -i representationType:0,answerId:0 | grep value0 | cut -d'"' -f4
yell Test issuing DID document...
testcontent=111111
doc_addr=$(everdev c r -n $network -s $signer DidRegistry issueDidDoc -i docOwnerPubKey:0x$(cat ~/tonkeys/$signer | grep public | cut -d'"' -f4),docOwnerAddress:0000000000000000000000000000000000000000000000000000000000000000,content:$testcontent,initialDocBalance:500000000,answerId:0 | grep didDocAddr | cut -d'"' -f4)
assert_not_empty "$doc_addr" "issueDidDoc failed"
yell "Document deployed: " $doc_addr
resultcontent=$(everdev c r -n $network -s $signer -a $doc_addr DidDocument getContent -i representationType:0,answerId:0 | grep value0 | cut -d'"' -f4)
if [[ "$testcontent" != "$resultcontent" ]]
then
    die getContent test failed. Got: "$resultcontent"
fi
yell $(f_green OK)