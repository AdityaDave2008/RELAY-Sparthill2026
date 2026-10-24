"""SDK wire contract tests, not live DynamoDB evidence."""
import json

import boto3
import pytest
from botocore.stub import Stubber, ANY

from relay_backend.store import Conflict, DynamoStore, Put


def adapter():
    client = boto3.client('dynamodb', region_name='us-east-1', aws_access_key_id='test-only', aws_secret_access_key='test-only')
    return client, DynamoStore(client, 'relay-messages')


def test_strong_read_and_conditional_write_wire_contract():
    client, store = adapter()
    pk = 'RELAY_MVP_V1#REQUEST#synthetic'
    with Stubber(client) as stub:
        stub.add_response('get_item', {'Item': {'pk': {'S': pk}, 'sk': {'S': 'META'}, 'v': {'N': '1'}, 'payload': {'S': '{"a":1}'}}},
                          {'TableName': 'relay-messages', 'Key': {'pk': {'S': pk}, 'sk': {'S': 'META'}}, 'ConsistentRead': True})
        assert store.get(pk, 'META') == ({'a': 1}, 1)
        stub.add_response('transact_write_items', {}, {'TransactItems': [{'Put': {
            'TableName': 'relay-messages', 'Item': {'pk': {'S': pk}, 'sk': {'S': 'META'}, 'v': {'N': '2'}, 'payload': {'S': '{"a":2}'}},
            'ConditionExpression': 'v = :v', 'ExpressionAttributeValues': {':v': {'N': '1'}}}}]})
        store.transact(puts=[Put(pk, 'META', {'a': 2}, 1)])
        stub.assert_no_pending_responses()


def test_namespace_and_conditional_conflict_fail_closed():
    client, store = adapter()
    with pytest.raises(ValueError):
        store.get('OTHER_PROJECT', 'META')
    with Stubber(client) as stub:
        stub.add_client_error('transact_write_items', service_error_code='TransactionCanceledException',
                              service_error_meta={}, expected_params={'TransactItems': ANY},
                              modeled_fields={'CancellationReasons': [{'Code': 'ConditionalCheckFailed', 'Message': 'synthetic conflict'}]})
        with pytest.raises(Conflict):
            store.transact(puts=[Put('RELAY_MVP_V1#REQUEST#synthetic', 'META', {'a': 1})])
