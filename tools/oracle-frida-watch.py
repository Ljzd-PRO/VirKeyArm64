"""Attach quickly when Solidcam.exe appears; Windows Frida lacks spawn gating."""
import argparse
import json
import pathlib
import sys
import time

import frida

p = argparse.ArgumentParser()
p.add_argument('--output', required=True)
p.add_argument('--wait', type=int, default=40)
p.add_argument('--capture', type=int, default=60)
p.add_argument('--server', default='127.0.0.1:27042')
p.add_argument('--process', default='Solidcam.exe')
a = p.parse_args()
device = frida.get_device_manager().add_remote_device(a.server)
source = pathlib.Path(__file__).with_name('oracle-deviceio.js').read_text()
started = time.monotonic()
process = None
while time.monotonic() - started < a.wait:
    try:
        process = device.get_process(a.process)
        break
    except frida.ProcessNotFoundError:
        time.sleep(0.005)
if process is None:
    raise SystemExit(a.process + ' did not start')
session = device.attach(process.pid)
script = session.create_script(source)
with open(a.output, 'w', encoding='utf-8') as out:
    def on_message(message, data):
        if message['type'] == 'send':
            out.write(json.dumps(message['payload']) + '\n')
            out.flush()
        else:
            print(message, file=sys.stderr, flush=True)
    script.on('message', on_message)
    script.load()
    print('attached', process.pid, 'after', round(time.monotonic()-started, 2),
          'seconds', flush=True)
    time.sleep(a.capture)
    script.unload()
    session.detach()
