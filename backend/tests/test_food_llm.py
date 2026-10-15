import pytest
from fastapi import HTTPException


def test_missing_food_configuration_is_actionable(monkeypatch):
    from food_config import validate_food_config
    monkeypatch.delenv("NEO4J_PASSWORD", raising=False)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    with pytest.raises(RuntimeError, match="NEO4J_PASSWORD.*OPENAI_API_KEY"):
        validate_food_config()


def test_openai_model_and_output(monkeypatch):
    pytest.importorskip("openai")
    import openai
    from types import SimpleNamespace
    from food_llm import generate_text

    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test-key")
    monkeypatch.setenv("OPENAI_MODEL", "gpt-4o-mini")

    calls = []

    class MockCompletions:
        def create(self, **kwargs):
            calls.append(kwargs)
            choice = SimpleNamespace(message=SimpleNamespace(content="openai analysis"))
            return SimpleNamespace(choices=[choice])

    class MockChat:
        completions = MockCompletions()

    class MockOpenAI:
        def __init__(self, **kwargs):
            self.chat = MockChat()

    monkeypatch.setattr(openai, "OpenAI", MockOpenAI)
    assert generate_text("test prompt") == "openai analysis"
    assert calls[0]["model"] == "gpt-4o-mini"
    assert calls[0]["messages"][0]["content"] == "test prompt"


def test_openai_errors_do_not_expose_secrets_or_return_success(monkeypatch):
    pytest.importorskip("openai")
    import openai
    from food_llm import generate_text

    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.setenv("OPENAI_API_KEY", "sk-secret-key-123")

    def fail(**kwargs):
        raise RuntimeError("provider error with sk-secret-key-123")

    monkeypatch.setattr(openai, "OpenAI", fail)
    with pytest.raises(HTTPException) as result:
        generate_text("test")
    assert result.value.status_code == 503
    assert "sk-secret-key-123" not in result.value.detail


def test_gemini_errors_do_not_expose_secrets_or_return_success(monkeypatch):
    pytest.importorskip("google.genai")
    import google.genai as genai
    from food_llm import generate_text
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setenv("GEMINI_API_KEY", "private-test-key")
    def fail(**kwargs):
        raise RuntimeError("provider error with private-test-key")
    monkeypatch.setattr(genai, "Client", fail)
    with pytest.raises(HTTPException) as result:
        generate_text("test")
    assert result.value.status_code == 503
    assert "private-test-key" not in result.value.detail


def test_gemini_model_and_output(monkeypatch):
    pytest.importorskip("google.genai")
    import google.genai as genai
    from types import SimpleNamespace
    from food_llm import generate_text
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setenv("GEMINI_API_KEY", "private-test-key")
    monkeypatch.setenv("GEMINI_MODEL", "configured-model")
    calls = []
    class Client:
        def __init__(self, **kwargs):
            self.models = self
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass
        def generate_content(self, **kwargs):
            calls.append(kwargs)
            return SimpleNamespace(text="gemini analysis")
    monkeypatch.setattr(genai, "Client", Client)
    assert generate_text("test prompt") == "gemini analysis"
    assert calls[0]["model"] == "configured-model"
    assert calls[0]["contents"] == "test prompt"

