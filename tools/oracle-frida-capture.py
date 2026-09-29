import argparse
import json
import pathlib
import sys
import time

import frida

parser = argparse.ArgumentParser()
parser.add_argument('--pid', type=int, required=True)
parser.add_argument('--seconds', type=int, default=60)
parser.add_argument('--output', required=True)
parser.add_argument('--server', default='127.0.0.1:27042')
args = parser.parse_args()
device = frida.get_device_manager().add_remote_device(args.server)
session = device.attach(args.pid)
source = pathlib.Path(__file__).with_name('oracle-deviceio.js').read_text()
script = session.create_script(source)
with open(args.output, 'w', encoding='utf-8') as out:
    def on_message(message, data):
        if message['type'] == 'send':
            out.write(json.dumps(message['payload'], ensure_ascii=False) + '\n')
            out.flush()
        else:
            print(message, file=sys.stderr, flush=True)
    script.on('message', on_message)
    script.load()
    print('attached', args.pid, flush=True)
    try:
        time.sleep(args.seconds)
    finally:
        script.unload()
        session.detach()
