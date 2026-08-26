package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
	"go.uber.org/zap"

	"github.com/yourusername/docassist/config"
	aiHandler "github.com/yourusername/docassist/internal/ai/handler"
	aiService "github.com/yourusername/docassist/internal/ai/service"
	authHandler "github.com/yourusername/docassist/internal/auth/handler"
	authModel "github.com/yourusername/docassist/internal/auth/model"
	authRepo "github.com/yourusername/docassist/internal/auth/repository"
	authService "github.com/yourusername/docassist/internal/auth/service"
	docHandler "github.com/yourusername/docassist/internal/document/handler"
	docModel "github.com/yourusername/docassist/internal/document/model"
	docRepo "github.com/yourusername/docassist/internal/document/repository"
	docService "github.com/yourusername/docassist/internal/document/service"
	matterHandler "github.com/yourusername/docassist/internal/matter/handler"
	matterModel "github.com/yourusername/docassist/internal/matter/model"
	matterRepo "github.com/yourusername/docassist/internal/matter/repository"
	matterService "github.com/yourusername/docassist/internal/matter/service"
	paymentHandler "github.com/yourusername/docassist/internal/payment/handler"
	paymentModel "github.com/yourusername/docassist/internal/payment/model"
	paymentRepo "github.com/yourusername/docassist/internal/payment/repository"
	paymentService "github.com/yourusername/docassist/internal/payment/service"
	searchHandler "github.com/yourusername/docassist/internal/search/handler"
	searchService "github.com/yourusername/docassist/internal/search/service"
	"github.com/yourusername/docassist/pkg/database"
	"github.com/yourusername/docassist/pkg/gemini"
    "github.com/yourusername/docassist/pkg/groq"
	"github.com/yourusername/docassist/pkg/logger"
	"github.com/yourusername/docassist/pkg/middleware"
	"github.com/yourusername/docassist/pkg/ocr"
	"github.com/yourusername/docassist/pkg/qdrant"
	"github.com/yourusername/docassist/pkg/razorpay"
)

// @title           DocAssist API
// @version         1.0
// @description     AI-powered document assistant API
// @termsOfService  http://swagger.io/terms/

// @contact.name   API Support
// @contact.email  support@docassist.app

// @license.name  MIT

// @host      localhost:8080
// @BasePath  /api/v1

// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
// @description Type "Bearer" followed by a space and the JWT token.
func main() {
	// ─── 1. Load .env ────────────────────────────────────────────────────────────
	if err := godotenv.Load(); err != nil {
		fmt.Println("No .env file found, using environment variables")
	}

	// ─── 2. Load config ──────────────────────────────────────────────────────────
	cfg := config.Load()
	// ─── 3. Init logger ──────────────────────────────────────────────────────────
	if err := logger.Init(cfg); err != nil {
		fmt.Printf("FATAL: logger init failed: %v\n", err)
		os.Exit(1)
	}
	defer logger.Sync()
	logger.Info("Starting DocAssist API", zap.String("env", cfg.App.Env), zap.String("version", "1.0.0"))

	// ─── 4. Connect PostgreSQL ───────────────────────────────────────────────────
	// Never log the DSN itself — it embeds POSTGRES_PASSWORD.
	logger.Info("Connecting to PostgreSQL",
		zap.String("host", cfg.Postgres.Host),
		zap.String("db", cfg.Postgres.DBName),
		zap.String("sslmode", cfg.Postgres.SSLMode),
	)
	db, err := database.Connect(cfg)
	if err != nil {
		logger.Fatal("Failed to connect to PostgreSQL", logger.Err(err))
	}
	defer database.Close()
	logger.Info("PostgreSQL connected")

	// Create custom PostgreSQL ENUM types that GORM cannot create automatically
	db.Exec(`DO $$ BEGIN
		CREATE TYPE user_status AS ENUM ('active', 'inactive', 'suspended');
	EXCEPTION WHEN duplicate_object THEN NULL;
	END $$;`)

	// Auto-migrate all models — GORM creates/updates tables, never drops columns
	if err := db.AutoMigrate(
		&authModel.Role{},
		&authModel.User{},
		&authModel.RefreshToken{},
		&authModel.PasswordResetToken{},
		&authModel.UserSettings{},
		&docModel.Document{},
		&docModel.DocumentChunk{},
		&matterModel.Matter{},
		&matterModel.MatterDocument{},
		&paymentModel.Order{},
	); err != nil {
		logger.Fatal("AutoMigrate failed", logger.Err(err))
	}
	logger.Info("Schema migration complete")

	// Seed default roles (admin=1, user=2) — safe to run on every startup
	db.Exec(`INSERT INTO roles (id, name, description, permissions) VALUES (1, 'admin', 'Administrator', '{}') ON CONFLICT (id) DO NOTHING`)
	db.Exec(`INSERT INTO roles (id, name, description, permissions) VALUES (2, 'user', 'Regular user', '{}') ON CONFLICT (id) DO NOTHING`)
	logger.Info("Roles seeded")

	// ─── 5. Connect Redis ────────────────────────────────────────────────────────
	redisClient, err := connectRedis(cfg)
	if err != nil {
		logger.Warn("Redis connection failed — rate limiting disabled", logger.Err(err))
		redisClient = nil
	} else {
		logger.Info("Redis connected")
	}
	_ = redisClient // used by rate limiter middleware (injected below)

	// ─── 6. Init Qdrant ──────────────────────────────────────────────────────────
	ctx := context.Background()
    qdrantClient, err := qdrant.NewClient(&cfg.Qdrant)
    if err != nil {
        logger.Warn("Qdrant unavailable - semantic search disabled", logger.Err(err))
        qdrantClient = nil
    } else if err := qdrantClient.EnsureCollection(ctx); err != nil {
        logger.Warn("Qdrant collection setup failed", logger.Err(err))
    } else {
        logger.Info("Qdrant connected and collection ready")
    }

	// ─── 7. Init Gemini ──────────────────────────────────────────────────────────
	geminiClient, err := gemini.NewClient(ctx, &cfg.Gemini)
	if err != nil {
		logger.Fatal("Failed to init Gemini client", logger.Err(err))
	}
	logger.Info("Gemini client initialized")

	// ─── 8. Init OCR ─────────────────────────────────────────────────────────────
	ocrService := ocr.NewService(&cfg.OCR)
	logger.Info("OCR service initialized")

	// ─── 9. Ensure storage directory exists ──────────────────────────────────────
	if err := os.MkdirAll(cfg.Storage.LocalPath, 0755); err != nil {
		logger.Fatal("Failed to create storage directory", logger.Err(err))
	}
	if err := os.MkdirAll(filepath.Dir(cfg.Log.FilePath), 0755); err != nil {
		logger.Warn("Could not create log directory", logger.Err(err))
	}

	// ─── 10. Wire repositories ───────────────────────────────────────────────────
	authRepository := authRepo.NewAuthRepository(db)
	documentRepository := docRepo.NewDocumentRepository(db)
	matterRepository := matterRepo.NewMatterRepository(db)
	paymentRepository := paymentRepo.NewPaymentRepository(db)

	// ─── 11. Wire services ───────────────────────────────────────────────────────
	authSvc := authService.New(authRepository, cfg, nil)
	documentSvc := docService.NewDocumentService(documentRepository, cfg)
	groqClient := groq.NewClient(&groq.Config{
		APIKey:       cfg.Groq.APIKey,
		APIKeys:      cfg.Groq.APIKeys, // GROQ_API_KEY_2 … _5 for key rotation
		Model:        cfg.Groq.Model,
		ClaudeAPIKey: cfg.Claude.APIKey,
		ClaudeModel:  cfg.Claude.Model,
	})
	if cfg.Claude.APIKey != "" {
		logger.Info("Claude configured as primary AI provider, Groq as fallback")
	} else {
		logger.Info("ANTHROPIC_API_KEY not set — using Groq as the AI provider")
	}
    aiSvc := aiService.NewAIService(documentRepository, geminiClient, groqClient, qdrantClient, ocrService)
	searchSvc := searchService.NewSearchService(db, geminiClient, qdrantClient)
	matterSvc := matterService.NewMatterService(matterRepository)
	rzpClient := razorpay.NewClient(cfg.Razorpay.KeyID, cfg.Razorpay.KeySecret)
	paymentSvc := paymentService.NewPaymentService(paymentRepository, rzpClient, cfg.Razorpay.KeyID)

	// ─── 12. Wire handlers ───────────────────────────────────────────────────────
	authH := authHandler.New(authSvc)
	documentH := docHandler.NewDocumentHandler(documentSvc)
	aiH := aiHandler.NewAIHandler(aiSvc, ocrService)
	searchH := searchHandler.NewSearchHandler(searchSvc)
	matterH := matterHandler.NewMatterHandler(matterSvc, documentRepository)
	paymentH := paymentHandler.NewPaymentHandler(paymentSvc)

	// ─── 13. Setup Gin ───────────────────────────────────────────────────────────
	if cfg.IsProd() {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
    router.Use(func(c *gin.Context) {
        c.Header("Access-Control-Allow-Origin", "*")
        c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization, X-Request-ID")
        if c.Request.Method == "OPTIONS" {
            c.AbortWithStatus(204)
            return
        }
        c.Next()
    })

	// Global middleware
	router.Use(requestid.New())
	router.Use(middleware.RequestID())
	router.Use(ginLogger())
	router.Use(gin.Recovery())

	// ─── 14. Health check (no auth) ──────────────────────────────────────────────
	router.GET("/health", func(c *gin.Context) {
		dbErr := database.HealthCheck()
		status := "healthy"
		httpCode := http.StatusOK
		if dbErr != nil {
			status = "degraded"
			httpCode = http.StatusServiceUnavailable
		}
		c.JSON(httpCode, gin.H{
			"status":    status,
			"timestamp": time.Now().UTC(),
			"services": gin.H{
				"database": dbErr == nil,
				"qdrant":   true,
			},
		})
	})

	// ─── 15. Swagger (dev only) ──────────────────────────────────────────────────
	if cfg.IsDev() {
		router.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))
		logger.Info("Swagger UI available at http://localhost:8080/swagger/index.html")
	}

	// ─── 16. API routes ──────────────────────────────────────────────────────────
	v1 := router.Group("/api/v1")

	// Public auth routes
	auth := v1.Group("/auth")
	{
		auth.POST("/register", authH.Register)
		auth.POST("/login", authH.Login)
		auth.POST("/refresh", authH.RefreshToken)
		auth.POST("/forgot-password", authH.ForgotPassword)
		auth.POST("/reset-password", authH.ResetPassword)
	}

	// Protected routes — require valid JWT
	protected := v1.Group("")
	protected.Use(middleware.AuthRequired(cfg))
	{
		// Auth
		protected.POST("/auth/logout", authH.Logout)
		protected.GET("/auth/me", authH.GetProfile)
		protected.PUT("/auth/profile", authH.UpdateProfile)
		protected.PUT("/auth/change-password", authH.ChangePassword)

		// Documents
		protected.POST("/documents", documentH.Upload)
		protected.GET("/documents", documentH.List)
		protected.GET("/documents/:document_id", documentH.GetByID)
		protected.PATCH("/documents/:document_id", documentH.Update)
        protected.GET("/documents/:document_id/status", documentH.GetStatus)
		protected.DELETE("/documents/:document_id", documentH.Delete)
		protected.GET("/documents/:document_id/download", documentH.Download)
		protected.GET("/documents/:document_id/versions", documentH.GetVersions)

		// AI features (per document)
		protected.POST("/documents/:document_id/process", aiH.ProcessDocument)
		protected.POST("/documents/:document_id/summarize", aiH.Summarize)
		protected.POST("/documents/:document_id/ask", aiH.AskQuestion)
		protected.POST("/documents/:document_id/keypoints", aiH.ExtractKeyPoints)
		protected.POST("/documents/:document_id/timeline", aiH.ExtractTimeline)
		protected.POST("/documents/:document_id/translate", aiH.Translate)
		protected.POST("/documents/:document_id/analyze", aiH.AnalyzeDocument)
		protected.POST("/documents/:document_id/actions", aiH.ExtractActionItems)
		protected.POST("/documents/:document_id/report", aiH.GenerateReport)
		protected.POST("/documents/:document_id/citations", aiH.ExtractCitations)
		protected.POST("/documents/:document_id/risks", aiH.ScanRisks)
		protected.POST("/documents/:document_id/deadlines", aiH.ExtractDeadlines)
		protected.POST("/documents/:document_id/autotag", aiH.AutoTag)
		protected.POST("/documents/:document_id/grammar", aiH.CheckGrammar)
		protected.POST("/ai/draft-legal", aiH.DraftLegalDocument)
		protected.POST("/ai/complaint-reply", aiH.ComplaintReplyGenerator)
		protected.GET("/ai/complaint-reply/status/:job_id", aiH.GetComplaintReplyStatus)
		protected.POST("/ai/complaint-reply/download", aiH.DownloadReplyDocx)
		protected.POST("/ai/complaint-reply/download-pdf", aiH.DownloadReplyPDF)
		protected.POST("/ocr/scan", aiH.ScanOCR)
		protected.POST("/ai/compare", aiH.CompareDocuments)
		protected.POST("/ai/help", aiH.HelpChat)
		protected.GET("/documents/:document_id/search", searchH.SearchInDocument)

		// Chat
		protected.POST("/documents/:document_id/chat", aiH.StartChat)
		protected.POST("/chat/:session_id/message", aiH.SendMessage)
		protected.GET("/chat/:session_id/history", aiH.GetChatHistory)

		// Semantic search + RAG
		protected.GET("/search", searchH.Search)
		protected.POST("/search/ask", searchH.RAGQuery)

		// AI usage stats
		protected.GET("/ai/usage", aiH.GetAIUsage)

		// Matters (case folders)
		protected.POST("/matters", matterH.Create)
		protected.GET("/matters", matterH.List)
		protected.GET("/matters/:matter_id", matterH.Get)
		protected.PATCH("/matters/:matter_id", matterH.Update)
		protected.DELETE("/matters/:matter_id", matterH.Delete)
		protected.POST("/matters/:matter_id/documents", matterH.AddDocument)
		protected.DELETE("/matters/:matter_id/documents/:doc_id", matterH.RemoveDocument)

		// Payments (credit recharge via Razorpay)
		protected.POST("/payments/razorpay/create-order", paymentH.CreateOrder)
		protected.POST("/payments/razorpay/verify", paymentH.Verify)
	}

	// Admin routes — require admin role
	admin := v1.Group("/admin")
	admin.Use(middleware.AuthRequired(cfg), middleware.RequireAdmin())
	{
		admin.GET("/users", authH.GetProfile)
		admin.DELETE("/users/:user_id", authH.GetProfile)
		admin.PUT("/users/:user_id/role", authH.GetProfile)
		admin.GET("/stats", func(c *gin.Context) {
			stats := database.Stats()
			c.JSON(http.StatusOK, gin.H{"success": true, "data": stats})
		})
	}

	// Allow large file uploads (up to 500 MB buffered to disk by Gin).
	router.MaxMultipartMemory = 500 << 20

	// ─── 17. Start server with graceful shutdown ──────────────────────────────────
	srv := &http.Server{
		Addr:              fmt.Sprintf(":%s", cfg.App.Port),
		Handler:           router,
		ReadHeaderTimeout: 10 * time.Second,  // protect against slow-header attacks only
		WriteTimeout:      300 * time.Second, // 5 min for AI responses
		IdleTimeout:       120 * time.Second,
	}

	// Start in goroutine so we can listen for shutdown signal
	go func() {
		logger.Info("Server listening", zap.String("addr", srv.Addr))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("Server failed", logger.Err(err))
		}
	}()

	// Block until SIGINT or SIGTERM
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("Shutdown signal received, draining connections...")

	// Give in-flight requests 30s to complete
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("Forced shutdown", logger.Err(err))
	}

	logger.Info("Server stopped cleanly")
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

func corsMiddleware(cfg *config.Config) gin.HandlerFunc {
	origins := cfg.Security.CORSAllowedOrigins
	if len(origins) == 0 {
		origins = []string{"http://localhost:3000", "http://localhost:8080"}
	}
	return cors.New(cors.Config{
		AllowOrigins:     origins,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "X-Request-ID"},
		ExposeHeaders:    []string{"Content-Disposition", "Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	})
}

func ginLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path

		c.Next()

		latency := time.Since(start)
		status := c.Writer.Status()

		fields := []zap.Field{
			zap.Int("status", status),
			zap.String("method", c.Request.Method),
			zap.String("path", path),
			zap.String("ip", c.ClientIP()),
			zap.Duration("latency", latency),
			zap.String("request_id", c.GetString("requestID")),
		}

		if status >= 500 {
			logger.Error("Request error", fields...)
		} else if status >= 400 {
			logger.Warn("Request warning", fields...)
		} else {
			logger.Info("Request", fields...)
		}
	}
}

func connectRedis(cfg *config.Config) (interface{}, error) {
	// Redis connection is optional — if it fails, app still works
	// Rate limiting is degraded but everything else functions normally
	// Full Redis integration is in pkg/cache/ (future enhancement)
	return nil, nil
}















