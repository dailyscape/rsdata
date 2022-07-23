'''
Conversion of wiki import script to python for performance reasons
@todo run time output (maybe later)
'''
import os
import requests
import json

# Env vars
api_updated_file = os.environ.get('API_UPDATED_FILE') or './rsapiupdated.json'
items_out_file = os.environ.get('API_DATA_FILE') or './rsdata.js'
alch_out_file = os.environ.get('API_DATA_ALCH_FILE') or './rsdataalch.js'
watch_out_file = os.environ.get('API_DATA_WATCH_FILE') or './rsdatawatch.js'
items_data_file = os.environ.get('ITEMS_DATA_FILE') or './rsitems.json'
alch_data_file = os.environ.get('ALCH_DATA_FILE') or './rsitemsalch.json'
watch_data_file = os.environ.get('WATCH_DATA_FILE') or './rsitemswatch.json'
image_output_dir = os.environ.get('IMAGE_OUTPUT_DIR') or './images'
api_items_directory = os.environ.get('API_ITEM_DIRECTORY') or './items/'
api_search_file = os.environ.get('API_SEARCH_FILE') or './rsapidatawikisearch.js'

items_out = {}
alch_out = {}
watch_out = {}
search_out = {}
total_items = 0

def load_json_file(filename):
    with open(filename) as f:
        data = json.load(f)
    f.close()
    return data

def write_apidata_file(filename, apidata):
    json_out = json.dumps(apidata, separators=(',', ':'))
    js_out = 'var rsapidata=' + json_out + ';'
    with open(filename, 'w') as f:
        f.write(js_out)
    f.close()

last_updated = load_json_file(api_updated_file)
items_data = load_json_file(items_data_file)
alch_data = load_json_file(alch_data_file)
watch_data = load_json_file(watch_data_file)

# Load wiki bulk data
wiki_url = 'https://chisel.weirdgloop.org/gazproj/gazbot/rs_dump.json'
wiki_response = requests.get(wiki_url)

if wiki_response.status_code != 200:
    print('error retrieving remote data')
    sys.exit(1)

wiki_data = json.loads(wiki_response.content)

if wiki_data['%UPDATE_DETECTED%'] <= last_updated['updated']:
    print('no new data')

else:
    #Parse wiki items
    for wiki_id, wiki_item in wiki_data.items():
        if not wiki_id.isnumeric():
            continue

        image_path = image_output_dir + '/' + wiki_id + '.gif'
        if not os.path.isfile(image_path):
            print(f'saving {wiki_id}.gif')
            image_download = requests.get('https://secure.runescape.com/m=itemdb_rs/obj_sprite.gif?id=' + wiki_id)
            if image_download.status_code != 200:
                print(f'error retrieving {wiki_id}.gif')
            else:
                open(image_path, 'wb').write(image_download.content)

        if wiki_id in items_data:
            items_out[wiki_id] = {'name': wiki_item['name'], 'price': wiki_item['price'], 'last': wiki_item['last']}

        if wiki_id in alch_data:
            alch_out[wiki_id] = {'name': wiki_item['name'], 'price': wiki_item['price'], 'last': wiki_item['last'], 'highalch': wiki_item['highalch']}

        if wiki_id in watch_data:
            if 'elyid' in watch_data[wiki_id]:
                watch_out[wiki_id] = {'name': wiki_item['name'], 'price': wiki_item['price'], 'last': wiki_item['last'], 'elyid': watch_data[wiki_id]['elyid']}
            else:
                watch_out[wiki_id] = {'name': wiki_item['name'], 'price': wiki_item['price'], 'last': wiki_item['last']}

        search_out[wiki_id] = wiki_item['name']

        with open(api_items_directory + wiki_id + '.json', 'w') as outfile:
            json.dump(wiki_item, outfile, ensure_ascii=False, separators=(',', ':'))

        total_items += 1

    # create search file for future enhancments
    search_json_out = json.dumps({int(x):search_out[x] for x in search_out.keys()}, sort_keys=True, separators=(',\n', ':'))
    search_js_out = 'var rssearchdata = \n' + search_json_out + ';'
    with open(api_search_file, 'w') as f:
        f.write(search_js_out)
    f.close()

    # output to files
    write_apidata_file(items_out_file, items_out)
    write_apidata_file(alch_out_file, alch_out)
    write_apidata_file(watch_out_file, watch_out)

    # save api updated timestamp
    updated = {'updated': wiki_data['%UPDATE_DETECTED%']}
    with open(api_updated_file, 'w') as outfile:
        json.dump(updated, outfile)

    print(f'data saved - {total_items} items')
