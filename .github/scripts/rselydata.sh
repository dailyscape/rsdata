#!/bin/bash
# Ely.gg data

#@todo figure out how to encapsulate testing json, multiline function params don't seem to translate well

starttime=$(date +%s)

ELY_DATA_FILE=${ELY_DATA_FILE:="./rselydata.js"}
ELY_UPDATED_FILE=${ELY_UPDATED_FILE:="./rselyupdated.json"}
ELY_ITEMS_FILE=${ELY_ITEMS_FILE:="./rselyitems.json"}
ELY_MAP_FILE=${ELY_MAP_FILE:="./rselymap.json"}

olditemjson=$(<${ELY_ITEMS_FILE})
oldapidata=$(<${ELY_DATA_FILE})

curl_response=""
curl_status=0
testjson=0
items_success=1

getItemAPI ()
{
    local itemid=$1
    curl_response=$(curl -Ssf https://www.ely.gg/item/${itemid}/prices)
    curl_status=$?
}

#Check and load new full item list
curl_response=$(curl -Ssf https://www.ely.gg/all/itemlist)
curl_status=$?
if (( $curl_status > 0 )); then
    echo "curl error"
    exit ${curl_status}
fi

#test for valid json
jq -e . >/dev/null 2>&1 <<< $curl_response
testjson=$?
if (( $testjson > 0 )) && [[ "${curl_response}" != "${olditemjson}" ]]; then
    echo ${curl_response} > ${ELY_ITEMS_FILE}
fi

# Start getting individual item data
curl_response=""
itemjson=$(<${ELY_ITEMS_FILE})
itemmap=$(<${ELY_MAP_FILE})
new_data="{\n"
for itemrow in $(jq -crS '.[] | @base64' <<< ${itemjson}); do
    itemrow=$(base64 --decode <<< ${itemrow})
    itemid=$(jq -cr '.id' <<< ${itemrow})
    itemname=$(jq -cr '.name' <<< ${itemrow} | sed "s/[^A-Za-z0-9 ]//g" | xargs )
    itemdata=$(jq -cr --arg itemid "$itemid" .[\"$itemid\"] <<< ${itemmap})
    rsitemid=$(jq -cr .rsid <<< ${itemdata})

    echo "$itemid - $itemname"

    if [[ "${rsitemid}" == "-1" ]]; then
        continue
    fi

    getItemAPI ${itemid}
    test_data=$(echo -e "${curl_response}")
    jq -e . >/dev/null 2>&1 <<< $test_data
    testjson=$?
    if (( $testjson > 0 )) || (( $curl_status > 0 )); then
        echo "Error on item id: ${itemid} - ${testjson} - ${curl_status}"
        items_success=0
        break
    fi

    #we want to get just data in the past 2 month and just the last 5 prices of those
    datefilter=$(date -d "$today -2 month" "+%Y-%m-%d")
    pricedata=$(jq -cr --arg datefilter "${datefilter}" '[.items[] | select(.date>=$datefilter)][:5]' <<< ${curl_response})
    testjson=$?
    if (( $testjson > 0 )); then
        pricedata="[]"
    fi

    #remap to rsid
    new_data+="\"${rsitemid}\":{\"elyname\": \"${itemname}\", \"elyid\": \"${itemid}\", \"elyprices\": ${pricedata}},\n"

    sleep 0.5
done
new_data="${new_data:0:-3}\n}"

test_data=$(echo -e "${new_data}")
jq -e . >/dev/null 2>&1 <<< $test_data
testjson=$?

endtime=$(date +%s)
runtime=$(( endtime - starttime ))
echo "Runtime: ${runtime}s"

#error or save
if (( $curl_status > 0 )); then
    echo "curl error"
    exit ${curl_status}
elif (( $testjson > 0 )) || (( $items_success < 1 )); then
    echo "json invalid"
    exit 1
else
    echo -e "var rselydata = ${new_data};" > ${ELY_DATA_FILE}

    newapidata=$(<${ELY_DATA_FILE})
    if [[ ${newapidata} != ${oldapidata} ]]; then
        echo -e "{\"updated\":${endtime}}" > ${ELY_UPDATED_FILE}
    fi

    echo "data saved"
fi
