"""Write non-secret CloudFormation parameters locally. Does not upload or deploy."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--config', type=Path, required=True)
p.add_argument('--code-key', required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
config = json.loads(a.config.read_text())
if config.get('mode') != 'aws' or config.get('storage') != 'dynamodb':
    raise SystemExit('Use the verified AWS-mode DynamoDB configuration')
if not a.code_key.startswith('cloud-mvp-v1/deploy/') or not a.code_key.endswith('.zip') or '..' in a.code_key:
    raise SystemExit('Use an isolated deployment object key')
for name in ('aws_config_file', 'aws_credentials_file', 'aws_login_cache_directory', 'local_public_key', 'worker_function_name'):
    config.pop(name, None)
config.update(aws_profile=None, runtime_dir='/tmp/relay')
parameters = {'ExecutionRoleArn': 'arn:aws:iam::928489693154:role/relay-cloud-mvp-execution',
              'CodeBucket': config.get('bucket_name', 'relay-artifacts-928489693154-use1'),
              'CodeKey': a.code_key, 'CognitoClientId': config['client_id'],
              'BackendSettingsJson': json.dumps(config, separators=(',', ':'))}
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps([{'ParameterKey': k, 'ParameterValue': v} for k, v in parameters.items()], indent=2) + '\n')
print('Prepared parameters; no AWS calls. Review hosting approval before deployment.')
