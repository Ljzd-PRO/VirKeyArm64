"""Attach to the next x64 hasplms service process and record device calls."""
import argparse
import json
import pathlib
import time
import frida

p = argparse.ArgumentParser()
p.add_argument('--previous-pid', type=int, required=True)
p.add_argument('--output', required=True)
p.add_argument('--wait', type=int, default=30)
p.add_argument('--capture', type=int, default=30)
p.add_argument('--server', default='127.0.0.1:27042')
a = p.parse_args()
device = frida.get_device_manager().add_remote_device(a.server)
end = time.monotonic() + a.wait
while time.monotonic() < end:
    try:
        process = device.get_process('hasplms.exe')
        if process.pid != a.previous_pid:
            break
    except frida.ProcessNotFoundError:
        pass
    time.sleep(0.05)
else:
    raise SystemExit('new hasplms process did not appear')
session = device.attach(process.pid)
source = pathlib.Path(__file__).with_name('oracle-deviceio.js').read_text()
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
    print('attached', process.pid, flush=True)
    try:
        time.sleep(a.capture)
    finally:
        script.unload()
        session.detach()
