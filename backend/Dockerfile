FROM python:3.12-slim
WORKDIR /app
COPY requirements-accounts.txt constraints-tested.txt ./
RUN pip install --no-cache-dir -r requirements-accounts.txt && useradd --create-home app
COPY account_api.py recovery.py ./
USER app
EXPOSE 8002
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8002/health', timeout=3)"
CMD ["uvicorn", "account_api:app", "--host", "0.0.0.0", "--port", "8002", "--no-proxy-headers"]
