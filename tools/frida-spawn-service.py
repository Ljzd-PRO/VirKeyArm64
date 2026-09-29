"""Capture device calls before a restarted Windows service executes startup code."""
import argparse
import json
import pathlib
import time
import frida

p = argparse.ArgumentParser()
p.add_argument('--server', required=True)
p.add_argument('--output', required=True)
p.add_argument('--wait', type=int, default=45)
a = p.parse_args()
device = frida.get_device_manager().add_remote_device(a.server)
source = pathlib.Path(__file__).with_name('oracle-deviceio.js').read_text()
sessions = []
scripts = []
captured = False

with open(a.output, 'w', encoding='utf-8') as out:
    def on_message(message, data):
        if message['type'] == 'send':
            out.write(json.dumps(message['payload'], ensure_ascii=False) + '\n')
            out.flush()
        else:
            print(message, flush=True)

    def on_spawn(spawn):
        global captured
        print('spawn', spawn.pid, spawn.identifier, flush=True)
        try:
            if spawn.identifier.lower().endswith('hasplms.exe'):
                session = device.attach(spawn.pid)
                script = session.create_script(source)
                script.on('message', on_message)
                script.load()
                sessions.append(session)
                scripts.append(script)
                captured = True
                print('attached', spawn.pid, flush=True)
        except Exception as e:
            print('attach failed', type(e).__name__, e, flush=True)
        finally:
            device.resume(spawn.pid)

    device.on('spawn-added', on_spawn)
    device.enable_spawn_gating()
    print('gating enabled', flush=True)
    try:
        end = time.monotonic() + a.wait
        while time.monotonic() < end:
            time.sleep(0.2)
            if captured and time.monotonic() > end - max(0, a.wait - 20):
                break
    finally:
        device.disable_spawn_gating()
        for script in scripts:
            try: script.unload()
            except Exception: pass
        for session in sessions:
            try: session.detach()
            except Exception: pass
