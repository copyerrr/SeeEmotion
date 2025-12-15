@echo off
echo ========================================
echo 모든 서버 시작 중...
echo ========================================
echo.
echo [1/4] 메인 FastAPI 서버 (포트 8000)
echo [2/4] WebSocket 서버 (포트 8001)
echo [3/4] 비디오 분석 서버 (포트 8002)
echo [4/4] Flutter 프론트엔드 (포트 3000)
echo.
echo 각 서버는 별도 창에서 실행됩니다.
echo 종료하려면 각 창에서 Ctrl+C를 누르세요.
echo.
pause

REM 현재 스크립트의 디렉토리 경로 저장
set SCRIPT_DIR=%~dp0
set BACKEND_DIR=%SCRIPT_DIR%backend
set FRONTEND_DIR=%SCRIPT_DIR%front

REM [1] 메인 FastAPI 서버 (포트 8000)
start "메인 API 서버 (8000)" cmd /k "cd /d %BACKEND_DIR% && python -m uvicorn main:app --host 0.0.0.0 --port 8000"

REM 잠시 대기
timeout /t 2 /nobreak >nul

REM [2] WebSocket 서버 (포트 8001)
start "WebSocket 서버 (8001)" cmd /k "cd /d %BACKEND_DIR% && python emotion_ws_server.py"

REM 잠시 대기
timeout /t 2 /nobreak >nul

REM [3] 비디오 분석 서버 (포트 8002)
start "비디오 분석 서버 (8002)" cmd /k "cd /d %BACKEND_DIR% && python video_analyzer_server.py"

REM 잠시 대기
timeout /t 2 /nobreak >nul

REM [4] Flutter 프론트엔드 (포트 3000)
start "Flutter 프론트엔드 (3000)" cmd /k "cd /d %FRONTEND_DIR% && flutter run -d chrome --web-hostname localhost --web-port 3000"

echo.
echo ========================================
echo 모든 서버가 시작되었습니다!
echo ========================================
echo.
echo 실행 중인 서버:
echo   - 메인 API: http://localhost:8000
echo   - WebSocket: ws://localhost:8001/ws/captions
echo   - 비디오 분석: http://localhost:8002
echo   - Flutter 앱: http://localhost:3000
echo.
echo 브라우저에서 http://localhost:3000 을 열어주세요!
echo.
pause
