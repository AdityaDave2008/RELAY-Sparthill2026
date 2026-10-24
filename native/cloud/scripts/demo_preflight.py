#!/usr/bin/env python3
"""Read-only demo checks. No AI invocation and no credential values in output."""
import argparse
import json
import platform
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from relay_backend.api import build_service
from relay_backend.common import PREFIX
from relay_backend.config import Settings


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True)
    parser.add_argument('--session-file',required=True);parser.add_argument('--output',required=True)
    args=parser.parse_args();report={'scope':'Read-only account/endpoint/budget checks; no AI or physical wireless check'}
    try:
        settings=Settings.load(args.config)
        url=urllib.parse.urlsplit(settings.public_base_url)
        if url.scheme!='https' or url.username or url.password or url.query or url.fragment:
            raise ValueError('Use a clean HTTPS demo base URL')
        opener=urllib.request.build_opener(NoRedirect())
        def request(url,body=None,headers=None):
            req=urllib.request.Request(url,headers=headers or {},data=json.dumps(body).encode() if body is not None else None)
            with opener.open(req,timeout=15) as response:return json.load(response),response.headers
        report['stage']='refresh_test_session'
        token=json.loads(Path(args.session_file).read_text())
        if token['expires']+978307200<time.time()+60:
            response,_=request('https://cognito-idp.us-east-1.amazonaws.com/',{'ClientId':settings.client_id,'AuthFlow':'REFRESH_TOKEN_AUTH','AuthParameters':{'REFRESH_TOKEN':token['refresh']}},{'Content-Type':'application/x-amz-json-1.1','X-Amz-Target':'AWSCognitoIdentityProviderService.InitiateAuth'})
            token['access']=response['AuthenticationResult']['AccessToken']
        report['stage']='public_health'
        health,headers=request(settings.public_base_url+'/v1/health')
        report['stage']='authenticated_profile'
        me,_=request(settings.public_base_url+'/v1/me',headers={'Authorization':'Bearer '+token['access']})
        report['stage']='authorized_directory'
        directory,_=request(settings.public_base_url+'/v1/shelters',headers={'Authorization':'Bearer '+token['access']})
        if me['subject']!=token['profile']['subject']:raise ValueError('Unexpected account')
        report.update(endpoint=settings.public_base_url,health=health['status'],role=me['role'],cache_control=headers.get('Cache-Control'),authorized_shelters=len(directory['items']),enrolled_receivers=sum(x.get('receiver') is not None for x in directory['items']))
        try:
            request(settings.public_base_url+'/v1/me');report['anonymous_status']='UNEXPECTED SUCCESS'
        except urllib.error.HTTPError as error:report['anonymous_status']=error.code
        report['stage']='aws_account_and_budget'
        service=build_service(settings)
        report['configured_caps']={'requests':settings.max_requests,'transcriptions':settings.max_transcriptions,'live_streams':settings.max_live_streams}
        report['used_allocations']={kind:(service.store.get(PREFIX+'BUDGET',kind) or ({'count':0},None))[0]['count'] for kind in ['requests','transcriptions']}
        if platform.system()=='Darwin':
            listing=subprocess.run(['ps','-axo','args='],capture_output=True,text=True,check=True).stdout.splitlines()
            report['local_worker_processes_seen']=sum(' -m relay_backend worker ' in x and str(Path(args.config).resolve()) in x for x in listing)
        report['stage']='complete'
        report['status']='PASS' if report['anonymous_status']==401 and health['mode']=='aws' else 'FAIL'
    except Exception as error:
        report.update(status='FAIL',error_type=type(error).__name__)
        if isinstance(error,urllib.error.HTTPError):
            report['http_status']=error.code
            try:report['api_error_code']=json.load(error).get('error',{}).get('code')
            except Exception:pass
        if hasattr(error,'response'):report['aws_error_code']=error.response.get('Error',{}).get('Code')
    Path(args.output).write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
    return 0 if report['status']=='PASS' else 1


if __name__=='__main__':raise SystemExit(main())
