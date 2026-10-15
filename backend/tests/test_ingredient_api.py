import json
from types import SimpleNamespace
import mongomock
import pytest
from fastapi.testclient import TestClient
import openai
import httpx
from account_api import app, database
from ingredient_api import LabelReview, DISCLAIMER


@pytest.fixture
def api_scanner(monkeypatch):
    db = mongomock.MongoClient(tz_aware=True).scanner_test
    app.dependency_overrides[database] = lambda: db
    monkeypatch.setenv('OPENAI_API_KEY', 'sk-test-not-real')
    client = TestClient(app)
    try:
        token = client.post('/auth/guest', json={'key': 'a' * 43}).json()['access_token']
        yield client, {'Authorization': 'Bearer ' + token}, db
    finally:
        client.close()
        app.dependency_overrides.clear()


def sample():
    return {'ingredients': [{'name': 'Oats', 'category': 'whole_food', 'note': 'Listed grain ingredient.'}],
            'summary': 'The label lists oats.', 'limitations': ['Amounts are unknown.']}


def mock_sdk(monkeypatch, parsed):
    class Fake:
        def __init__(self, **kwargs): self.responses = self
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def parse(self, **kwargs): return SimpleNamespace(output_parsed=parsed)
    monkeypatch.setattr(openai, 'OpenAI', Fake)


def test_real_sdk_structured_output_request_and_guest_flow(api_scanner, monkeypatch):
    client, headers, db = api_scanner
    requests = []
    def transport(request):
        requests.append(json.loads(request.content))
        return httpx.Response(200, json={
            'id': 'resp_test', 'object': 'response', 'created_at': 0,
            'model': 'gpt-4o-mini', 'status': 'completed',
            'output': [{'type': 'message', 'id': 'msg_test', 'status': 'completed',
                        'role': 'assistant', 'content': [{'type': 'output_text',
                        'text': json.dumps(sample()), 'annotations': []}]}],
        })
    sdk = openai.OpenAI
    monkeypatch.setattr(openai, 'OpenAI', lambda **kw:
        sdk(**kw, http_client=httpx.Client(transport=httpx.MockTransport(transport))))
    result = client.post('/extract_ingredients', headers=headers, json={'text': 'Ingredients: oats'})
    assert result.status_code == 200, result.text
    assert result.json()['ingredients'][0]['name'] == 'Oats'
    assert result.json()['source'] == 'openai'
    assert result.json()['disclaimer'] == DISCLAIMER
    assert requests[0]['store'] is False
    assert requests[0]['text']['format']['type'] == 'json_schema'
    assert requests[0]['input'][1]['content'] == 'Ingredients: oats'
    assert 'dailyLogs' not in db.users.find_one()


def test_auth_validation_and_status(api_scanner, monkeypatch):
    client, headers, _ = api_scanner
    assert client.post('/extract_ingredients', json={'text': 'oats'}).status_code == 401
    for text in ['', '   ', 'x' * 20001]:
        assert client.post('/extract_ingredients', headers=headers, json={'text': text}).status_code == 422
    assert client.get('/food/status').json()['analysis_configured'] is True
    monkeypatch.delenv('OPENAI_API_KEY')
    assert client.get('/food/status').json()['analysis_configured'] is False
    assert client.post('/extract_ingredients', headers=headers, json={'text': 'oats'}).status_code == 503
    assert client.get('/health').status_code == 200


def test_chat_only_key_uses_existing_api_method(api_scanner, monkeypatch):
    client, headers, _ = api_scanner
    paths = []
    def transport(request):
        paths.append(request.url.path)
        if request.url.path.endswith('/responses'):
            return httpx.Response(403, json={'error': {'message': 'Endpoint permission denied', 'code': 'insufficient_permissions'}})
        return httpx.Response(200, json={'id': 'chatcmpl_test', 'object': 'chat.completion',
            'created': 0, 'model': 'gpt-4o-mini', 'choices': [{'index': 0,
            'finish_reason': 'stop', 'message': {'role': 'assistant', 'content': json.dumps(sample())}}]})
    sdk = openai.OpenAI
    monkeypatch.setattr(openai, 'OpenAI', lambda **kw:
        sdk(**kw, http_client=httpx.Client(transport=httpx.MockTransport(transport))))
    result = client.post('/extract_ingredients', headers=headers, json={'text': 'Ingredients: oats'})
    assert result.status_code == 200, result.text
    assert paths == ['/v1/responses', '/v1/chat/completions']


@pytest.mark.parametrize('parsed', [None, LabelReview(ingredients=[], summary='No list', limitations=[])])
def test_refusal_and_no_ingredients_are_actionable(api_scanner, monkeypatch, parsed):
    mock_sdk(monkeypatch, parsed)
    client, headers, _ = api_scanner
    assert client.post('/extract_ingredients', headers=headers, json={'text': 'unreadable'}).status_code == 422


def test_provider_errors_do_not_expose_key_or_label(api_scanner, monkeypatch):
    def fail(**kw): raise RuntimeError('sk-test-not-real private label')
    monkeypatch.setattr(openai, 'OpenAI', fail)
    client, headers, _ = api_scanner
    result = client.post('/extract_ingredients', headers=headers, json={'text': 'private label'})
    assert result.status_code == 503
    assert 'sk-test' not in result.text and 'private label' not in result.text


def test_scans_share_mongodb_rate_limit(api_scanner, monkeypatch):
    monkeypatch.setenv('AUTH_RATE_LIMIT', '2')
    mock_sdk(monkeypatch, LabelReview(**sample()))
    client, headers, _ = api_scanner
    for _ in range(2):
        assert client.post('/extract_ingredients', headers=headers, json={'text': 'oats'}).status_code == 200
    assert client.post('/extract_ingredients', headers=headers, json={'text': 'oats'}).status_code == 429


@pytest.mark.parametrize('status,code,reason', [(401, None, 'ai_key_rejected'),
    (429, 'insufficient_quota', 'ai_credit_exhausted')])
def test_provider_configuration_failures_are_identifiable_without_secrets(api_scanner, monkeypatch, status, code, reason):
    class ProviderFailure(Exception):
        status_code = status
    error = ProviderFailure('private provider payload sk-test-not-real')
    error.code = code
    def fail(**kw): raise error
    monkeypatch.setattr(openai, 'OpenAI', fail)
    client, headers, _ = api_scanner
    result = client.post('/extract_ingredients', headers=headers, json={'text': 'oats'})
    assert result.status_code == 503
    assert result.headers['X-FemWise-Error'] == reason
    assert 'sk-test' not in result.text
