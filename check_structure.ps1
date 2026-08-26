# ── Run this from PowerShell at C:\manuworks ──

Write-Host "`n=== PROJECT STRUCTURE CHECK ===" -ForegroundColor Cyan
Write-Host "Root: C:\manuworks`n" -ForegroundColor Gray

$files = @(
    # Phase 1 - Foundation
    @{ Path = "docker-compose.yml";                                         Label = "Docker Compose" },
    @{ Path = ".env";                                                       Label = ".env (secrets)" },
    @{ Path = ".env.example";                                               Label = ".env.example" },
    @{ Path = ".gitignore";                                                 Label = ".gitignore" },

    # Phase 2 - Database
    @{ Path = "backend\migrations\001_init.sql";                            Label = "DB schema" },
    @{ Path = "backend\migrations\002_indexes.sql";                         Label = "DB indexes" },

    # Phase 3 - Go Backend
    @{ Path = "backend\go.mod";                                             Label = "Go module" },
    @{ Path = "backend\Dockerfile";                                         Label = "Dockerfile" },
    @{ Path = "backend\.dockerignore";                                      Label = ".dockerignore" },
    @{ Path = "backend\config\config.go";                                   Label = "Config" },
    @{ Path = "backend\cmd\server\main.go";                                 Label = "Main entrypoint" },

    # pkg layer
    @{ Path = "backend\pkg\database\postgres.go";                           Label = "DB connection" },
    @{ Path = "backend\pkg\logger\logger.go";                               Label = "Logger" },
    @{ Path = "backend\pkg\middleware\jwt.go";                              Label = "JWT middleware" },
    @{ Path = "backend\pkg\middleware\rbac.go";                             Label = "RBAC middleware" },
    @{ Path = "backend\pkg\gemini\gemini.go";                               Label = "Gemini client" },
    @{ Path = "backend\pkg\ocr\tesseract.go";                               Label = "OCR service" },
    @{ Path = "backend\pkg\ocr\docx_reader.go";                             Label = "DOCX reader" },
    @{ Path = "backend\pkg\qdrant\qdrant.go";                               Label = "Qdrant client" },

    # internal/auth
    @{ Path = "backend\internal\auth\model\user.go";                        Label = "Auth model" },
    @{ Path = "backend\internal\auth\repository\auth_repository.go";        Label = "Auth repository" },
    @{ Path = "backend\internal\auth\service\auth_service.go";              Label = "Auth service" },
    @{ Path = "backend\internal\auth\handler\auth_handler.go";              Label = "Auth handler" },

    # internal/document
    @{ Path = "backend\internal\document\model\document.go";                Label = "Document model" },
    @{ Path = "backend\internal\document\repository\document_repository.go"; Label = "Doc repository" },
    @{ Path = "backend\internal\document\service\document_service.go";      Label = "Document service" },
    @{ Path = "backend\internal\document\handler\document_handler.go";      Label = "Document handler" },

    # internal/ai
    @{ Path = "backend\internal\ai\service\ai_service.go";                  Label = "AI service" },
    @{ Path = "backend\internal\ai\handler\ai_handler.go";                  Label = "AI handler" },

    # internal/search
    @{ Path = "backend\internal\search\service\search_service.go";          Label = "Search service" },
    @{ Path = "backend\internal\search\handler\search_handler.go";          Label = "Search handler" }
)

$found   = 0
$missing = 0
$missing_list = @()

foreach ($f in $files) {
    $full = Join-Path "C:\manuworks" $f.Path
    if (Test-Path $full) {
        $size = "{0,6} KB" -f [math]::Round((Get-Item $full).Length / 1KB, 1)
        Write-Host ("  [OK]      {0,-24} {1}" -f $f.Label, $f.Path) -ForegroundColor Green
        $found++
    } else {
        Write-Host ("  [MISSING] {0,-24} {1}" -f $f.Label, $f.Path) -ForegroundColor Red
        $missing++
        $missing_list += $f.Path
    }
}

Write-Host "`n─────────────────────────────────────────────────────" -ForegroundColor Gray
Write-Host ("  Found  : {0} / {1} files" -f $found, $files.Count) -ForegroundColor Green

if ($missing -eq 0) {
    Write-Host "  Missing: 0 files" -ForegroundColor Green
    Write-Host "`n  All files present! Backend is complete." -ForegroundColor Cyan
    Write-Host "  Type 'next' to continue with Flutter frontend.`n" -ForegroundColor Cyan
} else {
    Write-Host ("  Missing: {0} files" -f $missing) -ForegroundColor Red
    Write-Host "`n  Files you need to create:" -ForegroundColor Yellow
    foreach ($m in $missing_list) {
        Write-Host "    - $m" -ForegroundColor Yellow
    }
    Write-Host ""
}
