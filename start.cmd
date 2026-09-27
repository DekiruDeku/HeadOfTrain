@echo off
setlocal
cd /d "%~dp0.."
echo Head of Train - A6 + B6
echo Open http://127.0.0.1:8765/ in your browser after the server starts.
echo Keep this window open. Press Ctrl+C to stop.
call tools\serve.cmd --host 127.0.0.1 --port 8765 %*
if errorlevel 1 pause
