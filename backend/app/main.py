from fastapi import FastAPI

from app.routers.health import router as health_router
from app.routers.resources import router as resources_router

app = FastAPI()

app.include_router(health_router)
app.include_router(resources_router)
