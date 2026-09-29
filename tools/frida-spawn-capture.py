"""Capture Win32 device calls from process entry in the Windows guest."""
import argparse
import json
import pathlib
import time
import frida

p = argparse.ArgumentParser()
p.add_argument('--server', required=True)
p.add_argument('--program', required=True)
p.add_argument('--arg', action='append', default=[])
p.add_argument('--output', required=True)
p.add_argument('--seconds', type=int, default=20)
p.add_argument('--kill', action='store_true')
a = p.parse_args()
device = frida.get_device_manager().add_remote_device(a.server)
source = pathlib.Path(__file__).with_name('oracle-deviceio.js').read_text()
pid = device.spawn([a.program, *a.arg])
print('spawned', pid, flush=True)
sessions = []
with open(a.output, 'w', encoding='utf-8') as out:
    def instrument(target_pid, label):
        session = device.attach(target_pid)
        script = session.create_script(source)
        def on_message(message, data):
            if message['type'] == 'send':
                out.write(json.dumps({'process':label,'pid':target_pid,
                                      **message['payload']},
                                     ensure_ascii=False) + '\n')
                out.flush()
            else:
                print(message, flush=True)
        script.on('message', on_message)
        script.load()
        session.enable_child_gating()
        sessions.append((session, script))

    def on_child(child):
        print('child', child.pid, child.identifier, flush=True)
        try:
            instrument(child.pid, child.identifier)
        except Exception as e:
            print('child attach failed', type(e).__name__, e, flush=True)
        finally:
            device.resume(child.pid)

    device.on('child-added', on_child)
    instrument(pid, a.program)
    device.resume(pid)
    print('resumed', pid, flush=True)
    try:
        time.sleep(a.seconds)
    finally:
        for session, script in reversed(sessions):
            try: script.unload()
            except frida.InvalidOperationError: pass
            try: session.detach()
            except frida.InvalidOperationError: pass
        if a.kill:
            try: device.kill(pid)
            except frida.ProcessNotFoundError: pass
