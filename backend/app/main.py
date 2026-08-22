from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.settings import settings
from app.routers.events import router as events_router
from app.routers.health import router as health_router
from app.routers.me import router as me_router
from app.routers.posts import router as posts_router
from app.routers.resources import router as resources_router

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_origin_regex=settings.cors_origin_regex,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(resources_router)
app.include_router(events_router)
app.include_router(posts_router)
app.include_router(me_router)
