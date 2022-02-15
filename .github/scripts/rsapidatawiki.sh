#!/bin/bash
# @see https://runescape.wiki/w/User:Gaz_Lloyd/using_gemw#Exchange_API

starttime=$(date +%s)

API_DATA_FILE=${API_DATA_FILE:="./rsapidatawiki.js"}
API_UPDATED_FILE=${API_UPDATED_FILE:="./rsapiupdated.json"}
ITEMS_DATA_FILE=${ITEMS_DATA_FILE:="./rsitems.json"}

itemjson=$(<${ITEMS_DATA_FILE})
oldapidata=$(<${API_DATA_FILE})

curl_response=""
curl_status=0
testjson=0

itemcount=0
itemstring=""

getItemsAPI ()
{
    local itemstring=$1
    curl_response+=$(curl -Ssf https://api.weirdgloop.org/exchange/history/rs/latest?id=${itemstring:0:-1})
    curl_status=$?
}

for itemid in $(jq -rS '. | keys[]' <<< ${itemjson}); do
    (( itemcount++ ))
    itemstring+="${itemid}|"

    # API allows 100 item ids at a time
    if (( $itemcount % 100 == 0 )); then
        getItemsAPI ${itemstring}

        if (( $curl_status > 0 )); then
            break
        fi

        itemstring=""
        sleep 1
    fi
done

# @todo Kludgy way of handling the last batch of items
if (( $curl_status == 0 )) && (( $itemcount > 100 )); then
    getItemsAPI ${itemstring}
fi

#merge local items file with incoming data
if test "$curl_status" == "0"; then
    combined_response=$(jq -s 'reduce .[] as $item ({}; . * $item)' <<< ${curl_response})

    new_data="{\n"
    for row in $(jq -cr '.[]' <<< ${combined_response}); do
        itemid=$(jq -r '.id' <<< ${row})
        itemdata=$(jq -cr --arg itemid "$itemid" .[\"$itemid\"] <<< ${itemjson})
        itemmerged=$(jq -crs 'reduce .[] as $item ({}; . * $item) | del( .id, .timestamp, .volume)' <<< $(echo "${row} ${itemdata}"))
        new_data+="\"${itemid}\":${itemmerged},\n"
    done
    new_data="${new_data:0:-3}\n}"

    #test for valid json
    test_data=$(echo -e $new_data)
    jq -e . >/dev/null 2>&1 <<< $test_data
    testjson=$?
fi

endtime=$(date +%s)
runtime=$(( endtime - starttime ))
echo "Runtime: ${runtime}s"

#error or save
if (( $curl_status > 0 )); then
    echo "curl error"
    exit ${curl_status}
elif (( $testjson > 0 )); then
    echo "json invalid"
    exit 1
else
    echo -e "var rsapidata = ${new_data};" > ${API_DATA_FILE}

    newapidata=$(<${API_DATA_FILE})
    if [[ ${newapidata} != ${oldapidata} ]]; then
        echo -e "{\"updated\":${endtime}}" > ${API_UPDATED_FILE}
    fi

    echo "data saved"
fi
