#!/bin/bash
# @see https://runescape.wiki/w/User:Gaz_Lloyd/using_gemw#Exchange_API
# @todo slim down main page data file more (e.g. doesn't need watchlist items)

starttime=$(date +%s)

API_DATA_FILE=${API_DATA_FILE:="./rsapidatawikibulk.js"}
API_SEARCH_FILE=${API_SEARCH_FILE:="./rsapidatawikisearch.js"}
API_UPDATED_FILE=${API_UPDATED_FILE:="./rsapiupdated.json"}
API_ITEM_DIRECTORY=${API_ITEM_DIRECTORY:="./items/"}
ITEMS_DATA_FILE=${ITEMS_DATA_FILE:="./rsitems.json"}
IMAGE_OUTPUT_DIR=${IMAGE_OUTPUT_DIR:="./images"}

itemjson=$(<${ITEMS_DATA_FILE})
oldapidata=$(<${API_DATA_FILE})
lastupdated=$(<${API_UPDATED_FILE})
lastupdated=$(jq -r '.updated' <<< ${lastupdated})

curl_response=""
curl_status=0
testjson=0
newremotedata=0
totalitems=0

curl_response+=$(curl -Ssf https://chisel.weirdgloop.org/gazproj/gazbot/rs_dump.json)
curl_status=$?

if test "$curl_status" == "0"; then
    #test for valid json
    test_data=$(echo -e $curl_response)
    jq -e . >/dev/null 2>&1 <<< $test_data
    testjson=$?

    if (( $testjson < 1 )); then
        #test old date vs new date before committing to writing all these files
        remoteupdated=$(jq -r '."%UPDATE_DETECTED%"' <<< ${curl_response})
        if (( $remoteupdated > $lastupdated )); then
            new_data="{\n"
            search_data="{\n"

            for item in $(jq -cr '.[] | @base64' <<< ${curl_response}); do
                item=$(base64 --decode <<< ${item})
                if [[ "${item}" == *"name"* ]]; then
                    itemid=$(jq -r '.id' <<< ${item})

                    if [[ "${itemid}" != "" ]]; then
                        itemname=$(jq -r '.name' <<< ${item})
                        search_data+="\"${itemid}\":\"${itemname}\",\n"

                        if [[ ! -f "${IMAGE_OUTPUT_DIR}/${itemid}.gif" ]]; then
                            wget -nd -r -O "${IMAGE_OUTPUT_DIR}/${itemid}.gif" -A jpeg,jpg,bmp,gif,png https://secure.runescape.com/m=itemdb_rs/obj_sprite.gif?id=${itemid}
                        fi

                        itemdata=$(jq -cr --arg itemid "$itemid" .[\"$itemid\"] <<< ${itemjson})
                        if [[ "${itemdata}" != "null" ]]; then
                            itemmerged=$(jq -crs 'reduce .[] as $item ({}; . * $item) | del(.id, .timestamp, .volume, .name_pt)' <<< $(echo "${item} ${itemdata}"))
                            new_data+="\"${itemid}\":${itemmerged},\n"
                        fi

                        echo $item > "${API_ITEM_DIRECTORY}${itemid}.json"

                        (( totalitems++ ))
                    fi
                fi
            done

            new_data="${new_data:0:-3}\n}"
            search_data="${search_data:0:-3}\n}"
            newremotedata=1

            #test for valid json
            test_data=$(echo -e $new_data)
            jq -e . >/dev/null 2>&1 <<< $test_data
            testjson=$?
        fi
    fi
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
elif (( $newremotedata > 0 )); then
    echo -e "var rsapidata = ${new_data};" > ${API_DATA_FILE}
    echo -e "var rssearchdata = ${search_data};" > ${API_SEARCH_FILE}
    echo -e "{\"updated\":${endtime}}" > ${API_UPDATED_FILE}
    echo "data saved - ${totalitems} items"
else
    echo "no new data"
    exit 0
fi
