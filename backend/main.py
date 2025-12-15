import uvicorn
import logging
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp
import os
from app import models
from app.database import engine
from app.routers import subtitles # 다른 라우터도 여기에 추가

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

# 앱 실행 시 DB 테이블 자동 생성 (테이블 없을 경우)
models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="The One Point API")

# ngrok 경고 페이지 우회 미들웨어
class NgrokSkipMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # ngrok-skip-browser-warning 헤더가 없으면 추가
        if "ngrok-skip-browser-warning" not in request.headers:
            request.scope["headers"].append((b"ngrok-skip-browser-warning", b"true"))
        
        response = await call_next(request)
        
        # 응답 헤더에도 추가 (일부 경우에 필요)
        response.headers["ngrok-skip-browser-warning"] = "true"
        return response

origins = [
    "http://localhost:3000",
    "http://localhost:8080",
    "http://127.0.0.1:8000",
    "*" # 개발 중에는 모든 곳에서 허용하는 것이 정신건강에 좋습니다.
]

# CORS 설정 (TV 앱이나 프론트엔드에서 접속 허용)
# 미들웨어 순서가 중요: CORS는 다른 미들웨어보다 먼저 등록되어야 함
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # 보안상 실제 배포시엔 프론트엔드 주소로 변경 권장
    allow_credentials=False,  # allow_origins=["*"]와 함께 사용할 수 없으므로 False로 변경
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"],  # DELETE 명시적 허용
    allow_headers=["*", "ngrok-skip-browser-warning"],  # ngrok 헤더 명시적 허용
    expose_headers=["*"],
)

app.add_middleware(NgrokSkipMiddleware)

# 라우터 등록
from app.routers import accounts, profiles, caption_modes, caption_settings

app.include_router(accounts.router)
app.include_router(profiles.router)
app.include_router(caption_modes.router)
app.include_router(caption_settings.router)
app.include_router(subtitles.router)

# WebSocket 엔드포인트 추가 (emotion_ws_server.py 통합)
from fastapi import WebSocket, WebSocketDisconnect
from typing import Set

connected_clients: Set[WebSocket] = set()

@app.websocket("/ws/captions")
async def captions_ws(websocket: WebSocket):
    """Flutter가 접속하는 WebSocket 엔드포인트"""
    await websocket.accept()
    connected_clients.add(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        connected_clients.discard(websocket)

def broadcast_caption(caption_data: dict):
    """caption payload를 모든 WebSocket 클라이언트에 broadcast"""
    import asyncio
    import json
    dead: Set[WebSocket] = set()
    for client in connected_clients:
        try:
            asyncio.create_task(client.send_text(json.dumps(caption_data)))
        except:
            dead.add(client)
    for client in dead:
        connected_clients.discard(client)

# 프론트엔드 정적 파일 서빙
FRONTEND_PATH = os.path.join(os.path.dirname(__file__), "..", "flutter_app_jisu-main", "build", "web")

if os.path.exists(FRONTEND_PATH):
    # API 경로는 제외하고 나머지는 프론트엔드로
    app.mount("/static", StaticFiles(directory=os.path.join(FRONTEND_PATH, "assets")), name="static")
    
    @app.get("/{full_path:path}")
    async def serve_frontend(full_path: str, request: Request):
        # API 경로는 제외
        if full_path.startswith("api/") or full_path.startswith("ws/"):
            return {"error": "Not found"}
        
        file_path = os.path.join(FRONTEND_PATH, full_path)
        if os.path.exists(file_path) and os.path.isfile(file_path):
            response = FileResponse(file_path)
            # JavaScript와 HTML 파일에 대해 캐시 방지 헤더 추가
            if full_path.endswith('.js') or full_path.endswith('.html') or full_path.endswith('.dart.js'):
                response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
                response.headers["Pragma"] = "no-cache"
                response.headers["Expires"] = "0"
            return response
        else:
            # SPA 라우팅: index.html 반환
            response = FileResponse(os.path.join(FRONTEND_PATH, "index.html"))
            response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
            response.headers["Pragma"] = "no-cache"
            response.headers["Expires"] = "0"
            return response
else:
    @app.get("/")
    def read_root():
        return {"message": "Welcome to The One Point DX Server"}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)