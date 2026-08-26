package database

import (
	"fmt"
	"log"
	"time"

	"github.com/yourusername/docassist/config"
	"gorm.io/driver/postgres"
    _ "github.com/lib/pq"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
	"gorm.io/gorm/schema"
)

// DB is the global database instance
var DB *gorm.DB

// Connect initializes the PostgreSQL connection using GORM.
// Call this once at application startup.
func Connect(cfg *config.Config) (*gorm.DB, error) {
	// --------------------------------------------------------
	// GORM Logger — verbose in dev, silent in prod
	// --------------------------------------------------------
	logLevel := logger.Info
	if cfg.IsProd() {
		logLevel = logger.Warn
	}

	gormLogger := logger.New(
		log.New(log.Writer(), "\r\n", log.LstdFlags),
		logger.Config{
			SlowThreshold:             200 * time.Millisecond, // Log queries slower than 200ms
			LogLevel:                  logLevel,
			IgnoreRecordNotFoundError: true, // Don't log "record not found" as error
			Colorful:                  cfg.IsDev(),
		},
	)

	// --------------------------------------------------------
	// Open connection
	// --------------------------------------------------------
	db, err := gorm.Open(postgres.Open(cfg.Postgres.DSN()), &gorm.Config{
		Logger: gormLogger,
		NamingStrategy: schema.NamingStrategy{
			SingularTable: false, // Use plural table names (users, documents, etc.)
		},
		// Disable default transaction for better performance on bulk ops
		SkipDefaultTransaction: false,
		// Prepare statements cache for repeated queries
		PrepareStmt: true,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	// --------------------------------------------------------
	// Connection Pool Settings
	// --------------------------------------------------------
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get sql.DB from gorm: %w", err)
	}

	sqlDB.SetMaxOpenConns(cfg.Postgres.MaxOpenConns)
	sqlDB.SetMaxIdleConns(cfg.Postgres.MaxIdleConns)
	sqlDB.SetConnMaxLifetime(cfg.Postgres.ConnMaxLifetime)
	sqlDB.SetConnMaxIdleTime(10 * time.Minute)

	// --------------------------------------------------------
	// Verify connection with ping
	// --------------------------------------------------------
	if err := sqlDB.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	DB = db
	log.Printf("✅ PostgreSQL connected: %s:%s/%s",
		cfg.Postgres.Host,
		cfg.Postgres.Port,
		cfg.Postgres.DBName,
	)

	return db, nil
}

// GetDB returns the global database instance.
// Panics if Connect() was not called first.
func GetDB() *gorm.DB {
	if DB == nil {
		log.Fatal("Database not initialized. Call database.Connect() first.")
	}
	return DB
}

// HealthCheck pings the database and returns an error if unhealthy.
// Used by the /health endpoint.
func HealthCheck() error {
	if DB == nil {
		return fmt.Errorf("database not initialized")
	}

	sqlDB, err := DB.DB()
	if err != nil {
		return fmt.Errorf("failed to get sql.DB: %w", err)
	}

	if err := sqlDB.Ping(); err != nil {
		return fmt.Errorf("database ping failed: %w", err)
	}

	return nil
}

// Stats returns database connection pool statistics.
// Useful for monitoring dashboards.
func Stats() map[string]interface{} {
	if DB == nil {
		return map[string]interface{}{"error": "database not initialized"}
	}

	sqlDB, err := DB.DB()
	if err != nil {
		return map[string]interface{}{"error": err.Error()}
	}

	stats := sqlDB.Stats()
	return map[string]interface{}{
		"max_open_connections": stats.MaxOpenConnections,
		"open_connections":     stats.OpenConnections,
		"in_use":               stats.InUse,
		"idle":                 stats.Idle,
		"wait_count":           stats.WaitCount,
		"wait_duration_ms":     stats.WaitDuration.Milliseconds(),
	}
}

// Close gracefully closes the database connection.
// Call this on application shutdown.
func Close() error {
	if DB == nil {
		return nil
	}

	sqlDB, err := DB.DB()
	if err != nil {
		return fmt.Errorf("failed to get sql.DB: %w", err)
	}

	if err := sqlDB.Close(); err != nil {
		return fmt.Errorf("failed to close database: %w", err)
	}

	log.Println("✅ Database connection closed")
	return nil
}

// WithTransaction runs a function inside a database transaction.
// Automatically commits on success and rolls back on error or panic.
//
// Usage:
//
//	err := database.WithTransaction(db, func(tx *gorm.DB) error {
//	    // do multiple DB ops here
//	    return nil
//	})
func WithTransaction(db *gorm.DB, fn func(tx *gorm.DB) error) error {
	tx := db.Begin()
	if tx.Error != nil {
		return fmt.Errorf("failed to begin transaction: %w", tx.Error)
	}

	// Recover from panic — rollback and re-panic
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
			panic(r)
		}
	}()

	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}

	if err := tx.Commit().Error; err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}


