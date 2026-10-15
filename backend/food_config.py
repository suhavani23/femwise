"""Food service configuration: credentials are supplied only on the backend."""
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).with_name(".env"))
NEO4J_URI = os.environ.get("NEO4J_URI", "bolt://127.0.0.1:7687")
NEO4J_USERNAME = os.environ.get("NEO4J_USERNAME", "neo4j")
NEO4J_PASSWORD = os.environ.get("NEO4J_PASSWORD", "")
CHROMA_DB_PATH = os.environ.get("CHROMA_DB_PATH", str(Path(__file__).resolve().parents[1] / ".local-data" / "chroma"))
COLLECTION_NAME = os.environ.get("CHROMA_COLLECTION", "cooked_dishes")
OLLAMA_API_BASE_URL = os.environ.get("OLLAMA_API_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL_NAME_EXTRACTION = os.environ.get("OLLAMA_MODEL", "adrienbrault/nous-hermes2pro:Q8_0")


def validate_food_config():
    missing = []
    if not os.environ.get("NEO4J_PASSWORD"):
        missing.append("NEO4J_PASSWORD")
    if not os.environ.get("OPENAI_API_KEY") and not os.environ.get("GEMINI_API_KEY"):
        missing.append("OPENAI_API_KEY (or GEMINI_API_KEY)")
    if missing:
        raise RuntimeError("Food analysis requires backend settings: " + ", ".join(missing))
