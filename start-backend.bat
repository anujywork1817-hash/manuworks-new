@echo off
echo Starting DocAssist Backend...

REM Stop local PostgreSQL to free port 5432
net stop postgresql-x64-17 2>nul
net stop postgresql-x64-18 2>nul

REM Start Docker containers
docker compose -f C:\manuworks\docker-compose.yml up -d postgres qdrant redis

REM Wait for services
timeout /t 5 /nobreak

REM Start backend
cd C:\manuworks\backend
go run ./cmd/server/main.go
