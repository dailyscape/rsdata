#!/bin/bash

ITEMS_DATA_FILE=${ITEMS_DATA_FILE:="./rsitems.json"}
IMAGE_OUTPUT_DIR=${IMAGE_OUTPUT_DIR:="./images"}

itemjson=$(<${ITEMS_DATA_FILE})

for itemid in $(jq -rS '. | keys[]' <<< ${itemjson}); do
    if [[ ! -f "${IMAGE_OUTPUT_DIR}/${itemid}.gif" ]]; then
        wget -nd -r -O "${IMAGE_OUTPUT_DIR}/${itemid}.gif" -A jpeg,jpg,bmp,gif,png https://secure.runescape.com/m=itemdb_rs/obj_sprite.gif?id=${itemid}
        sleep 0.1
    else
        echo "${itemid} already exists"
    fi
done
