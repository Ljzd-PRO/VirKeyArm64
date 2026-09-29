"""Capture device IOCTLs at SolidCAM startup on the x64 reference machine."""

import argparse
import json
import pathlib
import sys
import time

import frida

parser = argparse.ArgumentParser()
parser.add_argument('--seconds', type=int, default=120)
parser.add_argument('--output', required=True)
args = parser.parse_args()
device = frida.get_device_manager().add_remote_device('127.0.0.1:27042')
source = pathlib.Path(__file__).with_name('oracle-deviceio.js').read_text()
sessions = []

with open(args.output, 'w', encoding='utf-8') as out:
    def write(data):
        out.write(json.dumps(data, ensure_ascii=False) + '\n')
        out.flush()

    def on_spawn(spawn):
        name = spawn.identifier.lower()
        target = 'solidcam.exe' in name
        try:
            if target:
                session = device.attach(spawn.pid)
                script = session.create_script(source)
                script.on('message', lambda msg, binary, p=spawn.pid:
                          write({'pid': p, **msg['payload']}) if msg['type'] == 'send'
                          else print(msg, file=sys.stderr, flush=True))
                script.load()
                sessions.append((session, script))
                write({'kind': 'spawn', 'pid': spawn.pid, 'identifier': spawn.identifier})
        except Exception as error:
            write({'kind': 'attach-error', 'pid': spawn.pid, 'error': str(error)})
        finally:
            device.resume(spawn.pid)

    device.on('spawn-added', on_spawn)
    device.enable_spawn_gating()
    print('spawn gating enabled', flush=True)
    try:
        time.sleep(args.seconds)
    finally:
        device.disable_spawn_gating()
        for session, script in sessions:
            try:
                script.unload()
                session.detach()
            except Exception:
                pass
