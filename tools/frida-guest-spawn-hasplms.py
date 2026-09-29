"""Capture the guest license manager from process entry with Frida spawn."""
import argparse
import json
import pathlib
import time
import frida

p = argparse.ArgumentParser()
p.add_argument('--server', default='10.211.55.4:27043')
p.add_argument('--output', required=True)
p.add_argument('--seconds', type=int, default=20)
a = p.parse_args()
device = frida.get_device_manager().add_remote_device(a.server)
path = r'C:\Program Files (x86)\Common Files\Aladdin Shared\HASP\hasplms.exe'
source = pathlib.Path(__file__).with_name('oracle-deviceio.js').read_text()
pid = device.spawn([path, '-run'])
print('spawned', pid, flush=True)
session = device.attach(pid)
script = session.create_script(source)
with open(a.output, 'w', encoding='utf-8') as out:
    def on_message(message, data):
        if message['type'] == 'send':
            out.write(json.dumps(message['payload'], ensure_ascii=False) + '\n')
            out.flush()
        else:
            print(message, flush=True)
    script.on('message', on_message)
    script.load()
    device.resume(pid)
    print('resumed', pid, flush=True)
    try:
        time.sleep(a.seconds)
    finally:
        try: script.unload()
        except frida.InvalidOperationError: pass
        try: session.detach()
        except frida.InvalidOperationError: pass
        try: device.kill(pid)
        except frida.ProcessNotFoundError: pass
