import asyncio
from contextlib import asynccontextmanager
import json
import struct
from uuid import uuid4
import zlib

import pytest
from starlette.websockets import WebSocketDisconnect

from conftest import auth
from relay_backend.api import create_app
from relay_backend.auth import Principal
from relay_backend.common import APIError, PREFIX, key
from relay_backend.speech import (audio_event, decode_event, TranscriptAccumulator,
                                  claim_speech, finish_speech)
from fastapi.testclient import TestClient


def transcript_frame(text, partial):
    headers = b''
    for name, value in {':message-type':'event', ':event-type':'TranscriptEvent', ':content-type':'application/json'}.items():
        a,b=name.encode(),value.encode();headers+=bytes([len(a)])+a+bytes([7])+struct.pack('>H',len(b))+b
    body=json.dumps({'Transcript':{'Results':[{'ResultId':'segment1','StartTime':0,'IsPartial':partial,'Alternatives':[{'Transcript':text}]}]}}).encode()
    prelude=struct.pack('>II',16+len(headers)+len(body),len(headers))
    wire=prelude+struct.pack('>I',zlib.crc32(prelude))+headers+body
    return wire+struct.pack('>I',zlib.crc32(wire))


class FakeAWS:
    def __init__(self):self.queue=asyncio.Queue();self.audio=bytearray()
    async def send(self, data):
        headers,pcm=decode_event(data)
        assert headers[':event-type']=='AudioEvent'
        if pcm:
            self.audio.extend(pcm)
            if len(self.audio)==3200:await self.queue.put(transcript_frame('Shelter needs',True))
        else:
            await self.queue.put(transcript_frame('Shelter needs two water packs.',False))
            await self.queue.put(transcript_frame('Do not regress',True))
            await self.queue.put(None)
    def __aiter__(self):return self
    async def __anext__(self):
        value=await self.queue.get()
        if value is None:raise StopAsyncIteration
        return value


@pytest.fixture
def live(env):
    app=create_app(env['settings'],env['service']);calls=[]
    @asynccontextmanager
    async def factory(settings,identifier):
        upstream=FakeAWS();calls.append(upstream);yield upstream
    app.state.speech_factory=factory
    return TestClient(app),calls


def test_event_codec_checks_frame_and_both_checksums():
    frame=audio_event(b'\x01\x00'*1600)
    headers,pcm=decode_event(frame)
    assert headers=={':content-type':'application/octet-stream',':event-type':'AudioEvent',':message-type':'event'}
    assert pcm==b'\x01\x00'*1600
    for index in [0,5,9,13,len(frame)-1]:
        broken=bytearray(frame);broken[index]^=1
        with pytest.raises(ValueError):decode_event(bytes(broken))
    for bad in [frame[:-1],frame+b'x',b'',bytes(262145)]:
        with pytest.raises(ValueError):decode_event(bad)


def test_partial_replacement_order_and_final_does_not_regress():
    a=TranscriptAccumulator()
    def event(id,text,partial,start):return {'ResultId':id,'IsPartial':partial,'StartTime':start,'Alternatives':[{'Transcript':text}]}
    a.update(event('later','water',True,2));a.update(event('first','We need',False,0))
    a.update(event('later','two water packs',False,2))
    assert a.update(event('later','wrong partial',True,2)) is None
    assert a.final_text()=='We need two water packs'
    with pytest.raises(ValueError):a.update(event('bad','x'*4097,False,3))


def test_authenticated_stream_persists_before_complete_and_replays_without_new_provider(env,live):
    client,calls=live;identifier=str(uuid4())
    with client.websocket_connect('/v1/speech/'+identifier,headers=auth(env)) as ws:
        assert ws.receive_json()['type']=='ready'
        ws.send_bytes(bytes(3200));partial=ws.receive_json();assert partial['is_partial'] is True
        ws.send_json({'type':'finish'})
        assert ws.receive_json()['is_partial'] is False
        done=ws.receive_json();assert done['type']=='complete'
        stored=client.get('/v1/transcriptions/'+identifier,headers=auth(env))
        assert stored.status_code==200,stored.text
        assert stored.json()['status']=='completed'
        assert stored.json()['transcript']==done['text']
        assert stored.json()['duration_seconds']==0.1
    with client.websocket_connect('/v1/speech/'+identifier,headers=auth(env)) as ws:
        assert ws.receive_json()['cached'] is True
    assert len(calls)==1
    assert env['service'].store.get(PREFIX+'BUDGET','transcriptions')[0]['count']==1
    assert client.get('/v1/transcriptions/'+identifier,headers=auth(env,'test-requester-b')).status_code==404


def test_unauthorized_socket_never_allocates_or_calls_provider(env,live):
    client,calls=live
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect('/v1/speech/'+str(uuid4())):pass
    assert not calls
    assert env['service'].store.get(PREFIX+'BUDGET','transcriptions') is None


@pytest.mark.parametrize('packet,code',[(b'x','invalid_audio_chunk'),(bytes(8194),'invalid_audio_chunk'),({'type':'cancel'},'stream_cancelled'),({'type':'finish'},'empty_audio')])
def test_invalid_cancelled_empty_streams_fail_without_false_completion_and_release_lease(env,live,packet,code):
    client,calls=live;identifier=str(uuid4())
    with client.websocket_connect('/v1/speech/'+identifier,headers=auth(env)) as ws:
        assert ws.receive_json()['type']=='ready'
        if isinstance(packet,bytes):ws.send_bytes(packet)
        else:ws.send_json(packet)
        result=ws.receive_json();assert result['type']=='error' and result['code']==code
        record=env['service'].store.get(*key('transcription',identifier))[0]
        assert record['status']=='failed' and record['transcript'] is None
        owner=env['service'].store.get(*key('speech_owner',record['owner_subject']))[0]
        assert owner['expires_at']==0
    response=client.post('/v1/transcriptions/'+identifier+'/start',headers=auth(env),json={'operation_id':identifier})
    assert response.status_code==409 and response.json()['error']['code']=='stream_not_resumable'


def test_durable_limits_block_simultaneous_same_account_and_budget(env):
    service=env['service'];subject=next(k for k,v in env['settings'].memberships.items() if k=='test-requester-a')
    principal=Principal(subject,env['settings'].memberships[subject]);id=str(uuid4())
    record,slots=claim_speech(service,principal,id)
    with pytest.raises(APIError) as busy:claim_speech(service,principal,str(uuid4()))
    assert busy.value.code=='speech_busy'
    finish_speech(service,principal,id,slots,b'',error={'code':'cancelled','message':'test','retryable':False})
    env['settings'].max_transcriptions=1
    with pytest.raises(APIError) as limit:claim_speech(service,principal,str(uuid4()))
    assert limit.value.code=='demo_limit_reached'


def test_disconnection_never_marks_complete(env,live):
    client,_=live;identifier=str(uuid4())
    with client.websocket_connect('/v1/speech/'+identifier,headers=auth(env)) as ws:
        assert ws.receive_json()['type']=='ready'
        ws.send_bytes(bytes(3200));assert ws.receive_json()['is_partial']
        ws.close()
    # Session cleanup may finish after the client close; a processing record also
    # cannot be mistaken for completion. Lease expiration bounds crash recovery.
    row=env['service'].store.get(*key('transcription',identifier))[0]
    assert row['status']!='completed' and row['transcript'] is None


def test_crashed_stream_expires_and_retained_audio_can_be_retried(env):
    service=env['service'];subject='test-requester-a'
    principal=Principal(subject,env['settings'].memberships[subject]);identifier=str(uuid4())
    record,_=claim_speech(service,principal,identifier)
    service.clock=lambda:record['started_at']+service.settings.max_audio_seconds+46
    result=service.get_audio(principal,identifier)
    assert result['status']=='failed' and result['error']['code']=='stream_expired'
    # Expired owner/global leases permit a new explicit recording attempt.
    new,_=claim_speech(service,principal,str(uuid4()))
    assert new['status']=='processing'
