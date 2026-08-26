package config

import (
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	"github.com/joho/godotenv"
)

// Config holds all application configuration loaded from environment variables
type Config struct {
    Groq    GroqConfig
    Claude  ClaudeConfig
	App      AppConfig
	Postgres PostgresConfig
	Redis    RedisConfig
	JWT      JWTConfig
	Gemini   GeminiConfig
	Qdrant   QdrantConfig
	Storage  StorageConfig
	OCR      OCRConfig
	SMTP     SMTPConfig
	Security SecurityConfig
	Log      LogConfig
	Swagger  SwaggerConfig
	Razorpay RazorpayConfig
}

type AppConfig struct {
	Name    string
	Env     string
	Port    string
	BaseURL string
	Debug   bool
}

type PostgresConfig struct {
	Host            string
	Port            string
	User            string
	Password        string
	DBName          string
	SSLMode         string
	MaxOpenConns    int
	MaxIdleConns    int
	ConnMaxLifetime time.Duration
}

// DSN returns the PostgreSQL connection string
func (p PostgresConfig) DSN() string {
	return fmt.Sprintf(
		"postgresql://%s:%s@%s:%s/%s?sslmode=%s&TimeZone=UTC",
        p.User, p.Password, p.Host, p.Port, p.DBName, p.SSLMode,
	)
}

type RedisConfig struct {
	Host     string
	Port     string
	Password string
	DB       int
	CacheTTL time.Duration
}

// Addr returns host:port for Redis connection
func (r RedisConfig) Addr() string {
	return fmt.Sprintf("%s:%s", r.Host, r.Port)
}

type JWTConfig struct {
	AccessSecret  string
	RefreshSecret string
	AccessExpiry  time.Duration
	RefreshExpiry time.Duration
	Issuer        string
}

type GeminiConfig struct {
	APIKey              string
	Model               string
	ProModel            string
	EmbeddingModel      string
	MaxRequestsPerMin   int
	MaxTokensPerRequest int
	RequestTimeout      time.Duration
}

type QdrantConfig struct {
	Host           string
	Port           int
	GRPCPort       int
	APIKey         string
	CollectionName string
	VectorSize     int
}

// Addr returns host:port for Qdrant HTTP
func (q QdrantConfig) Addr() string {
	return fmt.Sprintf("http://%s:%d", q.Host, q.Port)
}

type StorageConfig struct {
	Type         string
	LocalPath    string
	MaxFileSize  int64
	AllowedTypes []string
}

type OCRConfig struct {
	TesseractPath string
	Lang          string
	Timeout       time.Duration
}

type SMTPConfig struct {
	Host      string
	Port      int
	Username  string
	Password  string
	FromName  string
	FromEmail string
	UseTLS    bool
}

type SecurityConfig struct {
	BcryptCost            int
	CORSAllowedOrigins    []string
	RateLimitRequests     int
	RateLimitWindow       time.Duration
	PasswordResetExpiry   time.Duration
	AuditLogRetentionDays int
}

type LogConfig struct {
	Level      string
	Format     string
	Output     string
	FilePath   string
	MaxSizeMB  int
	MaxBackups int
	MaxAgeDays int
}

type SwaggerConfig struct {
	Enabled  bool
	Host     string
	BasePath string
}

type RazorpayConfig struct {
	KeyID     string
	KeySecret string
}

// ============================================================
//  Singleton
// ============================================================

var cfg *Config

// Load reads the .env file and populates the Config struct.
// Call this once at application startup.
func Load() *Config {
	// Load .env file — ignore error if file doesn't exist (e.g. in Docker)
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, reading from environment")
	}

	cfg = &Config{
		App: AppConfig{
			Name:    getStr("APP_NAME", "DocAssist"),
			Env:     getStr("APP_ENV", "development"),
			Port:    getStrOr("PORT", "APP_PORT", "8080"), // PORT is set by Render/Railway/Fly.io
			BaseURL: getStr("APP_BASE_URL", "http://localhost:8080"),
			Debug:   getBool("APP_DEBUG", true),
		},

		Postgres: PostgresConfig{
			Host:            getStr("POSTGRES_HOST", "localhost"),
			Port:            getStr("POSTGRES_PORT", "5432"),
			User:            getStr("POSTGRES_USER", "docassist"),
			Password:        getStr("POSTGRES_PASSWORD", "secret123"),
			DBName:          getStr("POSTGRES_DB", "docassist_db"),
			SSLMode:         getStr("POSTGRES_SSL_MODE", "disable"),
			MaxOpenConns:    getInt("POSTGRES_MAX_OPEN_CONNS", 25),
			MaxIdleConns:    getInt("POSTGRES_MAX_IDLE_CONNS", 10),
			ConnMaxLifetime: getDuration("POSTGRES_CONN_MAX_LIFETIME", 5*time.Minute),
		},

		Redis: RedisConfig{
			Host:     getStr("REDIS_HOST", "localhost"),
			Port:     getStr("REDIS_PORT", "6380"),
			Password: getStr("REDIS_PASSWORD", "redissecret"),
			DB:       getInt("REDIS_DB", 0),
			CacheTTL: getDuration("REDIS_CACHE_TTL", 24*time.Hour),
		},

		JWT: JWTConfig{
			AccessSecret:  getStrRequired("JWT_ACCESS_SECRET"),
			RefreshSecret: getStrRequired("JWT_REFRESH_SECRET"),
			AccessExpiry:  getDuration("JWT_ACCESS_EXPIRY", 15*time.Minute),
			RefreshExpiry: getDuration("JWT_REFRESH_EXPIRY", 7*24*time.Hour),
			Issuer:        getStr("JWT_ISSUER", "docassist-api"),
		},

		Groq: GroqConfig{
			APIKey: getStr("GROQ_API_KEY", ""),
			APIKeys: func() []string {
				// Collect GROQ_API_KEY_2 … GROQ_API_KEY_5, skip blanks.
				extra := []string{}
				for i := 2; i <= 5; i++ {
					if k := getStr(fmt.Sprintf("GROQ_API_KEY_%d", i), ""); k != "" {
						extra = append(extra, k)
					}
				}
				return extra
			}(),
			Model: getStr("GROQ_MODEL", "openai/gpt-oss-120b"),
		},
        Claude: ClaudeConfig{
            APIKey: getStr("ANTHROPIC_API_KEY", ""),
            Model:  getStr("CLAUDE_MODEL", "claude-opus-5"),
        },
        Gemini: GeminiConfig{
			// Optional for local/dev runs with only a Groq key configured —
			// Gemini-backed features (semantic search, embeddings) are
			// skipped at startup instead of the app refusing to boot when
			// this is blank.
			APIKey:              getStr("GEMINI_API_KEY", ""),
			Model:               getStr("GEMINI_MODEL", "gemini-1.5-flash"),
			ProModel:            getStr("GEMINI_PRO_MODEL", "gemini-1.5-pro"),
			EmbeddingModel:      getStr("GEMINI_EMBEDDING_MODEL", "text-embedding-004"),
			MaxRequestsPerMin:   getInt("GEMINI_MAX_REQUESTS_PER_MIN", 14),
			MaxTokensPerRequest: getInt("GEMINI_MAX_TOKENS_PER_REQUEST", 8192),
			RequestTimeout:      getDuration("GEMINI_REQUEST_TIMEOUT", 30*time.Second),
		},

		Qdrant: QdrantConfig{
			Host:           getStr("QDRANT_HOST", "localhost"),
			Port:           getInt("QDRANT_PORT", 6333),
			GRPCPort:       getInt("QDRANT_GRPC_PORT", 6334),
			APIKey:         getStr("QDRANT_API_KEY", ""),
			CollectionName: getStr("QDRANT_COLLECTION_NAME", "docassist_vectors"),
			VectorSize:     getInt("QDRANT_VECTOR_SIZE", 768),
		},

		Storage: StorageConfig{
			Type:         getStr("STORAGE_TYPE", "local"),
			LocalPath:    getStr("STORAGE_LOCAL_PATH", "./storage"),
			MaxFileSize:  int64(getInt("STORAGE_MAX_FILE_SIZE", 524288000)),
			AllowedTypes: getStringSlice("STORAGE_ALLOWED_TYPES", []string{"pdf", "docx", "doc", "txt", "png", "jpg", "jpeg"}),
		},

		OCR: OCRConfig{
			TesseractPath: getStr("TESSERACT_PATH", "/usr/bin/tesseract"),
			Lang:          getStr("TESSERACT_LANG", "eng"),
			Timeout:       getDuration("TESSERACT_TIMEOUT", 60*time.Second),
		},

		SMTP: SMTPConfig{
			Host:      getStr("SMTP_HOST", "smtp.gmail.com"),
			Port:      getInt("SMTP_PORT", 587),
			Username:  getStr("SMTP_USERNAME", ""),
			Password:  getStr("SMTP_PASSWORD", ""),
			FromName:  getStr("SMTP_FROM_NAME", "DocAssist"),
			FromEmail: getStr("SMTP_FROM_EMAIL", "noreply@docassist.app"),
			UseTLS:    getBool("SMTP_USE_TLS", true),
		},

		Security: SecurityConfig{
			BcryptCost:            getInt("BCRYPT_COST", 12),
			CORSAllowedOrigins:    getStringSlice("CORS_ALLOWED_ORIGINS", []string{"http://localhost:3000"}),
			RateLimitRequests:     getInt("RATE_LIMIT_REQUESTS", 100),
			RateLimitWindow:       getDuration("RATE_LIMIT_WINDOW", time.Minute),
			PasswordResetExpiry:   getDuration("PASSWORD_RESET_EXPIRY", time.Hour),
			AuditLogRetentionDays: getInt("AUDIT_LOG_RETENTION_DAYS", 90),
		},

		Log: LogConfig{
			Level:      getStr("LOG_LEVEL", "debug"),
			Format:     getStr("LOG_FORMAT", "json"),
			Output:     getStr("LOG_OUTPUT", "stdout"),
			FilePath:   getStr("LOG_FILE_PATH", "./logs/app.log"),
			MaxSizeMB:  getInt("LOG_MAX_SIZE_MB", 100),
			MaxBackups: getInt("LOG_MAX_BACKUPS", 5),
			MaxAgeDays: getInt("LOG_MAX_AGE_DAYS", 30),
		},

		Swagger: SwaggerConfig{
			Enabled:  getBool("SWAGGER_ENABLED", true),
			Host:     getStr("SWAGGER_HOST", "localhost:8080"),
			BasePath: getStr("SWAGGER_BASE_PATH", "/api/v1"),
		},

		Razorpay: RazorpayConfig{
			KeyID:     getStr("RAZORPAY_KEY_ID", ""),
			KeySecret: getStr("RAZORPAY_KEY_SECRET", ""),
		},
	}

	return cfg
}

// Get returns the loaded config. Panics if Load() was not called first.
func Get() *Config {
	if cfg == nil {
		log.Fatal("Config not loaded. Call config.Load() first.")
	}
	return cfg
}

// IsProd returns true if running in production environment
func (c *Config) IsProd() bool {
	return c.App.Env == "production"
}

// IsDev returns true if running in development environment
func (c *Config) IsDev() bool {
	return c.App.Env == "development"
}

// ============================================================
//  Helper functions
// ============================================================

func getStr(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getStrOr(key1, key2, defaultVal string) string {
	if val := os.Getenv(key1); val != "" {
		return val
	}
	return getStr(key2, defaultVal)
}

// getStrRequired panics at startup if a required env var is missing
func getStrRequired(key string) string {
	val := os.Getenv(key)
	if val == "" {
		log.Fatalf("Required environment variable %q is not set", key)
	}
	return val
}

func getInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if i, err := strconv.Atoi(val); err == nil {
			return i
		}
	}
	return defaultVal
}

func getBool(key string, defaultVal bool) bool {
	if val := os.Getenv(key); val != "" {
		if b, err := strconv.ParseBool(val); err == nil {
			return b
		}
	}
	return defaultVal
}

func getDuration(key string, defaultVal time.Duration) time.Duration {
	if val := os.Getenv(key); val != "" {
		if d, err := time.ParseDuration(val); err == nil {
			return d
		}
	}
	return defaultVal
}

func getStringSlice(key string, defaultVal []string) []string {
	val := os.Getenv(key)
	if val == "" {
		return defaultVal
	}
	// Split comma-separated string
	var result []string
	for _, s := range splitAndTrim(val, ",") {
		if s != "" {
			result = append(result, s)
		}
	}
	return result
}

func splitAndTrim(s, sep string) []string {
	var result []string
	start := 0
	for i := 0; i <= len(s); i++ {
		if i == len(s) || s[i:i+len(sep)] == sep {
			part := trimSpace(s[start:i])
			result = append(result, part)
			start = i + len(sep)
		}
	}
	return result
}

func trimSpace(s string) string {
	start, end := 0, len(s)
	for start < end && (s[start] == ' ' || s[start] == '\t') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t') {
		end--
	}
	return s[start:end]
}






type GroqConfig struct {
    APIKey  string   // primary key (GROQ_API_KEY)
    APIKeys []string // additional keys for rotation (GROQ_API_KEY_2 … _5)
    Model   string
}

// ClaudeConfig holds the primary AI provider's settings. Groq (above) is
// used as the automatic fallback whenever Claude is unset or rate-limited.
type ClaudeConfig struct {
    APIKey string
    Model  string
}