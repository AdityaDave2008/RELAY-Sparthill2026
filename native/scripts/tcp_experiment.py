#!/usr/bin/env python3
"""Three separate processes; real Network.framework TCP on 127.0.0.1.
No Bonjour, radios, routing separation, iPhones, or physical P2P claims.
Terminates and restarts B with the same SQLite database between encounters.
"""
import datetime
import json
import os
import pathlib
import queue
import subprocess
import sys
import tempfile
import threading
import time
import uuid
ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = pathlib.Path(os.environ.get('RELAY_LAB_BINARY', str(ROOT / '.build/debug/RelayLab')))
log_lock = threading.Lock()
def log(text):
    with log_lock:
        print(datetime.datetime.now(datetime.timezone.utc).isoformat(), text, flush=True)
class Node:
    def __init__(self, role, db, identity=None):
        self.role, self.responses = role, queue.Queue()
        args = [str(BINARY), '--db', str(db), '--role', role]
        if identity: args += ['--id', identity]
        self.process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        self.events=[]
        def read():
            for line in self.process.stdout:
                value=json.loads(line)
                if 'event' in value:
                    self.events.append(value['event']); log(f'{role} {line.strip()}')
                else: self.responses.put(value)
        def errors():
            for line in self.process.stderr: log(f'{role} STDERR {line.strip()}')
        threading.Thread(target=read,daemon=True).start()
        threading.Thread(target=errors,daemon=True).start()
    def command(self, op, **fields):
        key=str(uuid.uuid4()); data=dict(op=op, request=key, **fields)
        self.process.stdin.write(json.dumps(data)+'\n'); self.process.stdin.flush()
        result=self.responses.get(timeout=12)
        assert result.get('request')==key, result
        assert result.get('ok'), result
        return result
    def snapshot(self): return self.command('snapshot')
    def crash(self):
        log(f'{self.role} deliberate SIGKILL after durable acceptance')
        self.process.kill(); self.process.wait(timeout=5)
    def quit(self):
        if self.process.poll() is None:
            self.command('quit'); self.process.wait(timeout=5)
    def wait(self, predicate, description):
        deadline=time.monotonic()+12
        while time.monotonic()<deadline:
            state=self.snapshot()
            if predicate(state): return state
            time.sleep(0.1)
        raise AssertionError(f'{self.role}: timeout: {description}: {state}')
def row(state, id): return next((m for m in state['messages'] if m['id']==id), None)

def main():
    log('REAL TCP LOOPBACK CONTROL ONLY — not a physical wireless test; all nodes on one Mac')
    identities={role:str(uuid.uuid4()) for role in 'ABC'}
    nodes=[]
    with tempfile.TemporaryDirectory(prefix='relay-tcp-control-') as tmp:
        dbs={role:pathlib.Path(tmp)/f'{role}.sqlite' for role in 'ABC'}
        try:
            a,b,c=[Node(role,dbs[role],identities[role]) for role in 'ABC']; nodes += [a,b,c]
            states=[n.wait(lambda s:s['port']>0,'listener ready') for n in (a,b,c)]
            log('IDENTITIES '+json.dumps(identities,sort_keys=True))
            m=a.command('compose',text='SYNTHETIC M001: Shelter A needs 20 water packs',destination=identities['C'])['message_id']
            log('ORIGINAL_MESSAGE_ID '+m)
            a.command('interrupt'); a.command('connect',port=states[1]['port'])
            a.wait(lambda s: row(s,m)['attempts']>=1 and not s['connected'],'interrupted connection closes')
            # Wait for receiver to observe EOF too before inspecting durable state.
            b.wait(lambda s:not s['connected'],'EOF after truncated frame')
            assert row(b.snapshot(),m) is None
            assert not row(a.snapshot(),m)['accepted_by'] and not row(a.snapshot(),m)['final_receipt']
            log('PASS control interruption: no destination insert or false ACK')
            a.command('connect',port=states[1]['port'])
            a.wait(lambda s:identities['B'] in row(s,m)['accepted_by'],'relay durable ACK')
            assert row(b.snapshot(),m)['hops']==1
            a.command('retransmit',id=m)
            b.wait(lambda s:any('DUPLICATE_SUPPRESSED id='+m in e for e in b.events),'duplicate received')
            assert len(b.snapshot()['messages'])==1
            log('PASS control A->B and duplicate suppression')
            a.command('stop'); b.crash()
            b=Node('B',dbs['B']); nodes.append(b)
            bs=b.wait(lambda s:s['port']>0,'restarted B listener')
            assert bs['device_id']==identities['B'] and row(bs,m)['hops']==1
            assert not row(a.snapshot(),m)['final_receipt']
            log('PASS actual B SIGKILL/restart: same device ID and message recovered from SQLite WAL')
            b.command('connect',port=states[2]['port'])
            cs=c.wait(lambda s:row(s,m) is not None,'C persisted original')
            bs=b.wait(lambda s:any(x['type']=='DELIVERY_RECEIPT' for x in s['messages']),'receipt returned to B')
            assert row(cs,m)['hops']==2
            receipt=next(x for x in bs['messages'] if x['type']=='DELIVERY_RECEIPT')
            assert receipt['original']==m
            b.command('retransmit',id=m)
            c.wait(lambda s:any('DUPLICATE_SUPPRESSED id='+m in e for e in c.events),'duplicate at C')
            assert len(c.snapshot()['messages'])==2
            assert not row(a.snapshot(),m)['final_receipt']
            log('PASS separate B->C encounter; one request, one receipt; A disconnected')
            c.command('stop'); b.quit()
            b=Node('B',dbs['B']); nodes.append(b)
            b.wait(lambda s:s['port']>0,'second B restart')
            a.command('start'); ast=a.wait(lambda s:s['port']>0,'A listener restart')
            b.command('connect',port=ast['port'])
            ast=a.wait(lambda s:bool(row(s,m)['final_receipt']),'final receipt returned to A')
            assert row(ast,m)['final_receipt']==receipt['id']
            assert row(ast,receipt['id'])['hops']==2
            log('PASS C->B->A receipt across second actual B process restart')
            for n in (a,b,c): log(n.role+' FINAL_SNAPSHOT '+json.dumps(n.snapshot(),sort_keys=True))
            log('PASS all TCP controls. Physical A–E = NOT TESTED. Infrastructure-independent wireless path = NOT VERIFIED.')
        finally:
            for node in nodes:
                try: node.quit()
                except Exception:
                    node.process.kill(); node.process.wait(timeout=5)
if __name__=='__main__': main()
