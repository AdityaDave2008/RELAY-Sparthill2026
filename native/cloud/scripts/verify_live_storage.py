"""Read-only independent AWS evidence check for the synthetic smoke results."""
import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import boto3


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', type=Path, required=True)
    p.add_argument('--smoke', type=Path, required=True)
    p.add_argument('--extra-result', type=Path, action='append', default=[])
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    cfg = json.loads(args.config.read_text())
    if cfg.get('mode') != 'aws' or cfg.get('storage') != 'dynamodb':
        raise SystemExit('Real AWS configuration required')
    for key, variable in [('aws_config_file','AWS_CONFIG_FILE'), ('aws_credentials_file','AWS_SHARED_CREDENTIALS_FILE'),
                          ('aws_login_cache_directory','AWS_LOGIN_CACHE_DIRECTORY')]:
        if cfg.get(key): os.environ[variable] = cfg[key]
    session = boto3.Session(profile_name=cfg.get('aws_profile', 'relay-workshop'), region_name='us-east-1')
    identity = session.client('sts').get_caller_identity()
    assert identity['Account'] == '928489693154'
    ddb, s3, transcribe = session.client('dynamodb'), session.client('s3'), session.client('transcribe')
    table = cfg.get('table_name', 'relay-messages')
    bucket = cfg.get('bucket_name', 'relay-artifacts-928489693154-use1')
    prefix = cfg.get('object_prefix', 'cloud-mvp-v1/')
    smoke = json.loads(args.smoke.read_text())
    requests = list(smoke['requests'])
    for path in args.extra_result:
        requests.append(json.loads(path.read_text())['result'])
    evidence = {'observed_at': datetime.now(timezone.utc).isoformat(), 'account': identity['Account'],
                'sts_request_id': identity['ResponseMetadata']['RequestId'], 'requests': [], 'transcriptions': []}
    for expected in requests:
        r = ddb.get_item(TableName=table, Key={'pk': {'S': 'RELAY_MVP_V1#REQUEST#' + expected['request_id']}, 'sk': {'S': 'META'}}, ConsistentRead=True)
        actual = json.loads(r['Item']['payload']['S'])
        for field in ['request_id','submission','cloud_state','analysis_state','result','provider_evidence']:
            assert actual[field] == expected[field], field
        evidence['requests'].append({'request_id': actual['request_id'], 'status': 'PASS', 'strongly_consistent_read': True,
                                     'ddb_request_id': r['ResponseMetadata']['RequestId'], 'analysis_state': actual['analysis_state']})
    for expected in smoke['transcriptions']:
        identifier = expected['transcription_id']
        r = ddb.get_item(TableName=table, Key={'pk': {'S': 'RELAY_MVP_V1#TRANSCRIPTION#' + identifier}, 'sk': {'S': 'META'}}, ConsistentRead=True)
        actual = json.loads(r['Item']['payload']['S'])
        assert actual['status'] == 'completed' and actual['transcript'] == expected['transcript']
        objects = []
        for suffix in ['uploads/' + identifier + '.wav', 'sealed/' + identifier + '.wav', 'transcripts/' + identifier + '.json']:
            object_key = prefix + suffix
            h = s3.head_object(Bucket=bucket, Key=object_key, ExpectedBucketOwner=identity['Account'])
            assert h['ServerSideEncryption'] == 'AES256'
            if suffix.endswith('.wav'): assert h['ContentLength'] == expected['byte_length']
            if suffix.startswith('sealed/'): assert h['Metadata']['sha256'] == expected['sha256']
            objects.append({'key': object_key, 'bytes': h['ContentLength'], 'encryption': h['ServerSideEncryption'], 'request_id': h['ResponseMetadata']['RequestId']})
        output = s3.get_object(Bucket=bucket, Key=prefix + 'transcripts/' + identifier + '.json', ExpectedBucketOwner=identity['Account'])
        try: transcript_json = json.loads(output['Body'].read(1_000_001))
        finally: output['Body'].close()
        assert transcript_json['results']['transcripts'][0]['transcript'] == expected['transcript']
        job = transcribe.get_transcription_job(TranscriptionJobName='relay-mvp-' + identifier)
        assert job['TranscriptionJob']['TranscriptionJobStatus'] == 'COMPLETED'
        assert job['TranscriptionJob']['Media']['MediaFileUri'] == 's3://' + bucket + '/' + prefix + 'sealed/' + identifier + '.wav'
        evidence['transcriptions'].append({'transcription_id': identifier, 'status': 'PASS', 'ddb_request_id': r['ResponseMetadata']['RequestId'],
                                          'job_name': 'relay-mvp-' + identifier, 'job_request_id': job['ResponseMetadata']['RequestId'],
                                          'transcript_matches_s3': True, 'objects': objects})
    owner = next(subject for subject, m in cfg['memberships'].items() if m['role'] == 'requester' and m['shelter_ids'] == ['shelter-a'])
    args_query = {'TableName': table, 'KeyConditionExpression': 'pk = :pk', 'ExpressionAttributeValues': {':pk': {'S': 'RELAY_MVP_V1#USER#' + owner}}, 'ConsistentRead': True}
    references = []
    while True:
        page = ddb.query(**args_query)
        references.extend(json.loads(x['payload']['S']) for x in page.get('Items', []))
        if not page.get('LastEvaluatedKey'): break
        args_query['ExclusiveStartKey'] = page['LastEvaluatedKey']
    calls = []
    for reference in references:
        r = ddb.get_item(TableName=table, Key={'pk': {'S': 'RELAY_MVP_V1#REQUEST#' + reference['request_id']}, 'sk': {'S': 'META'}}, ConsistentRead=True)
        payload = json.loads(r['Item']['payload']['S'])
        calls.append({'request_id': reference['request_id'], 'analysis_state': payload['analysis_state'], 'analysis_attempts': payload['analysis_attempts'], 'provider_evidence': payload.get('provider_evidence')})
    evidence['all_synthetic_request_results'] = calls
    evidence['accepted_request_count'] = len(references)
    queue = ddb.query(TableName=table, KeyConditionExpression='pk = :pk', ExpressionAttributeValues={':pk': {'S': 'RELAY_MVP_V1#WORK'}}, ConsistentRead=True, Limit=1)
    evidence['work_queue_empty'] = not bool(queue.get('Items'))
    assert evidence['work_queue_empty']
    evidence['status'] = 'PASS'
    args.output.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'status': 'PASS', 'verified_requests': len(evidence['requests']), 'verified_audio_jobs': len(evidence['transcriptions']),
                      'accepted_request_count': len(references), 'work_queue_empty': evidence['work_queue_empty']}, indent=2))


if __name__ == '__main__':
    main()
