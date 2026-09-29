"""Instrument SolidCAM before its launcher-created child runs."""
import argparse
import json
import pathlib
import sys
import time

import frida

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
parser.add_argument('--seconds', type=int, default=45)
parser.add_argument('--parent', default='sldworks.exe')
args = parser.parse_args()

device = frida.get_device_manager().add_remote_device('127.0.0.1:27042')
source = pathlib.Path(__file__).with_name('oracle-deviceio.js').read_text()
sessions = []
out = open(args.output, 'w', encoding='utf-8')

def instrument(pid, label):
    session = device.attach(pid)
    script = session.create_script(source)
    def on_message(message, data):
        if message['type'] == 'send':
            record = {'process': label, **message['payload']}
            out.write(json.dumps(record, ensure_ascii=False) + '\n')
            out.flush()
        else:
            print(message, file=sys.stderr, flush=True)
    script.on('message', on_message)
    script.load()
    sessions.append((session, script))
    return session

def on_delivered(child):
    print('child', child.pid, child.identifier, flush=True)
    try:
        instrument(child.pid, child.identifier)
    except Exception as exc:
        print('attach failed:', exc, file=sys.stderr, flush=True)
    finally:
        device.resume(child.pid)

device.on('child-added', on_delivered)
started = time.monotonic()
existing = {p.pid for p in device.enumerate_processes()
            if p.name.lower() == args.parent.lower()}
while time.monotonic() - started < 30:
    matches = [p for p in device.enumerate_processes()
               if p.name.lower() == args.parent.lower() and p.pid not in existing]
    if matches:
        launcher = matches[0]
        break
    time.sleep(0.05)
else:
    raise SystemExit(args.parent + ' did not start')
session = instrument(launcher.pid, args.parent)
session.enable_child_gating()
print('launcher gated', launcher.pid, 'after',
      round(time.monotonic() - started, 2), 'seconds', flush=True)
time.sleep(args.seconds)
for session, script in reversed(sessions):
    try:
        script.unload()
        session.detach()
    except frida.InvalidOperationError:
        pass
out.close()
