"""Validate the same MongoDB bearer sessions in each food service."""
from fastapi import Depends
from account_api import database, lifespan
from food_config import validate_food_config


def configure_food_api(app):
    @app.on_event("startup")
    async def connect_accounts():
        validate_food_config()
        context = lifespan(app)
        await context.__aenter__()
        app.state.account_context = context

    @app.on_event("shutdown")
    async def close_accounts():
        context = getattr(app.state, "account_context", None)
        if context is not None:
            await context.__aexit__(None, None, None)

    @app.get("/health")
    def health(db=Depends(database)):
        db.command("ping")
        return {"status": "ok", "storage": "mongodb"}
