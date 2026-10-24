"""Owner-only local sign-in helper. Reads existing synthetic users, never provisions accounts.
No credentials are printed, logged, embedded in the repo, or served through the API tunnel.
"""
import argparse,base64,hashlib,hmac,html,json,struct,time
from http.server import BaseHTTPRequestHandler,HTTPServer
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--identities',type=Path,required=True);p.add_argument('--port',type=int,default=8891);p.add_argument('--hours',type=float,default=2)
a=p.parse_args(); users=json.loads(a.identities.read_text()); deadline=time.time()+a.hours*3600

def code(secret,step):
 raw=hmac.new(base64.b32decode(secret+'='*(-len(secret)%8),casefold=True),struct.pack('>Q',step),hashlib.sha1).digest();o=raw[-1]&15
 return f'{(struct.unpack(">I",raw[o:o+4])[0]&0x7fffffff)%1000000:06d}'

class Handler(BaseHTTPRequestHandler):
 def log_message(self,*_): pass
 def do_GET(self):
  if self.path!='/' or self.headers.get('Host')!=f'127.0.0.1:{a.port}' or self.headers.get('Sec-Fetch-Site','none') not in {'none','same-origin'}:
   self.send_error(404);return
  step=int(time.time())//30
  cards=[]
  for actor,label in [('test-requester-a','Requester — iPhone 15 Pro Max'),('test-dispatcher-a','Dispatcher — iPhone 16 or Mac')]:
   u=users[actor];otp=code(u['totp_secret'],step)
   cards.append(f'''<article><h2>{html.escape(label)}</h2><label>Email</label><input readonly value="{html.escape(u['username'],quote=True)}"><label>Password</label><input type="password" readonly value="{html.escape(u['password'],quote=True)}"><button onclick="const p=this.previousElementSibling;p.type=p.type==='password'?'text':'password'">Show / hide password</button><label>Current authenticator code</label><strong>{otp}</strong></article>''')
  page='''<!doctype html><meta charset="utf-8"><title>Private RELAY demo sign-in</title><style>body{font:18px system-ui;max-width:850px;margin:40px auto;padding:20px;background:#f2f6f5;color:#17312d}article{background:white;padding:24px;margin:20px 0;border-radius:16px}label{display:block;margin-top:14px;font-size:14px}input{display:block;width:95%;font:16px monospace;padding:10px;margin:6px 0}button{padding:9px;font-size:15px}strong{display:block;font:32px monospace;margin-top:8px}</style><h1>Private RELAY demo sign-in</h1><p>This page is only on this Mac. Use these existing test accounts in RELAY's Cognito sign-in window. Do not share this page or its credentials with judges.</p><p>Codes refresh every 30 seconds. Use the current code when Cognito asks for MFA. Closing this helper does not sign you out of RELAY.</p>'''+''.join(cards)+'''<script>setTimeout(()=>location.reload(),'''+str(max(2000,(step+1)*30000-int(time.time()*1000)+500))+''')</script>'''
  data=page.encode();self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store');self.send_header('Cross-Origin-Resource-Policy','same-origin');self.send_header('X-Frame-Options','DENY');self.send_header('Content-Security-Policy',"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");self.end_headers();self.wfile.write(data)

server=HTTPServer(('127.0.0.1',a.port),Handler);server.timeout=1
print(f'Private local sign-in helper: http://127.0.0.1:{a.port}/ (no secrets in logs)',flush=True)
while time.time()<deadline: server.handle_request()
server.server_close()
