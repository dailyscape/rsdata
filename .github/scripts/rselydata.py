'''
Conversion of ely.gg import script to python for performance reasons
'''
import os
import sys
import requests
import json
import time
import re

# Env vars
ely_updated_file = os.environ.get('ELY_UPDATED_FILE') or './rselyupdated.json'
ely_items_file = os.environ.get('ELY_ITEMS_FILE') or './rselyitems.json'
ely_data_file = os.environ.get('ELY_DATA_FILE') or './rselydata.js'
ely_map_file = os.environ.get('ELY_MAP_FILE') or './rsitemswatch.json'

def load_json_file(filename):
    with open(filename) as f:
        data = json.load(f)
    return data

last_updated = load_json_file(ely_updated_file)
old_items = load_json_file(ely_items_file)
items_map = load_json_file(ely_map_file)

items_out = {}
total_items = 0

# Load ely items file
ely_url = 'https://www.ely.gg/all/itemlist'
ely_response = requests.get(ely_url)

if ely_response.status_code != 200:
    print('error retrieving remote data')
    sys.exit(1)

ely_data = json.loads(ely_response.content)

if ely_data != old_items:
    print('new items found')
    with open(ely_items_file, 'w') as outfile:
        json.dump(ely_data, outfile)

# dict comprehension to remap and enable quick lookup by elyid (commented out line saved for python 3.9)
# newmap = {v['elyid']: v | {'itemid': k} for k,v in items_map.items() if 'elyid' in v}
newmap = {v['elyid']: {**v, **{'itemid': k}} for k,v in items_map.items() if 'elyid' in v}

twomonthsago = time.gmtime(time.time() - (60 * 60 * 24 * 60))

# parse items
for ely_item in ely_data:
    elyname = re.sub(r"[^ A-Za-z0-9()'-]", "", " ".join(ely_item['name'].split())).replace("'", "%27")

    if elyname.lower().startswith(('deleted item', 'disabled')):
        print('skipping ' + elyname)
        continue

    mapped=newmap.get(str(ely_item['id']))

    if not mapped:
        rsitemid = 'ely-' + str(ely_item['id'])
    elif mapped.get('elyskip') == '1' or mapped.get('skip') == '1':
        print('skipping ' + elyname)
        continue
    else:
        rsitemid = mapped['itemid']

    print('getting ' + elyname + ' - ' + str(ely_item['id']))

    #now get individual item data
    item_url = 'https://www.ely.gg/item/' + str(ely_item['id']) + '/prices'
    item_response = requests.get(item_url)
    if item_response.status_code != 200:
        print('error getting item data for ' + str(ely_item['id']))
        continue
    item_data = json.loads(item_response.content)
    if 'error' in item_data:
        print('server error item: ' + str(ely_item['id']) + ' - ' + item_data['error'])
        continue

    #list of up to 5 prices within past 2 months (so we can avg it on the front end)
    pricedata = []
    pricecount = 0
    for item in item_data['items']:
        itemdate = time.strptime(item['date'], '%Y-%m-%d')

        if itemdate >= twomonthsago:
            pricedata.append(item)

        pricecount += 1
        if pricecount >= 5:
            break

    # or just the last price
    if len(pricedata) == 0:
        pricedata.append(item_data['items'][0])

    items_out[rsitemid] = {'elyname': elyname, 'elyid': str(ely_item['id']), 'elyprices': pricedata}
    total_items += 1
    time.sleep(0.1)

# write new data to file
json_out = json.dumps(items_out, separators=(',', ':'))
js_out = 'var rselydata=' + json_out + ';'
with open(ely_data_file, 'w') as f:
    f.write(js_out)

# save api updated timestamp
updated = {'updated': int(time.time())}
with open(ely_updated_file, 'w') as f:
    json.dump(updated, f)
