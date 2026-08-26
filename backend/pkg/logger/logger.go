package logger

import (
	"os"
	"path/filepath"

	"github.com/yourusername/docassist/config"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"gopkg.in/natefinch/lumberjack.v2"
)

// Log is the global logger instance
var Log *zap.Logger

// SugaredLog is the global sugared logger (printf-style)
var SugaredLog *zap.SugaredLogger

// Init initializes the global logger based on config.
// Call this once at application startup.
func Init(cfg *config.Config) error {
	// --------------------------------------------------------
	// Log Level
	// --------------------------------------------------------
	level, err := zapcore.ParseLevel(cfg.Log.Level)
	if err != nil {
		level = zapcore.InfoLevel
	}

	// --------------------------------------------------------
	// Encoder — JSON in prod, colored console in dev
	// --------------------------------------------------------
	var encoderCfg zapcore.EncoderConfig
	if cfg.IsProd() {
		encoderCfg = zap.NewProductionEncoderConfig()
	} else {
		encoderCfg = zap.NewDevelopmentEncoderConfig()
		encoderCfg.EncodeLevel = zapcore.CapitalColorLevelEncoder // Colored levels
	}

	encoderCfg.TimeKey = "timestamp"
	encoderCfg.EncodeTime = zapcore.ISO8601TimeEncoder // Human-readable time

	var encoder zapcore.Encoder
	if cfg.Log.Format == "json" {
		encoder = zapcore.NewJSONEncoder(encoderCfg)
	} else {
		encoder = zapcore.NewConsoleEncoder(encoderCfg)
	}

	// --------------------------------------------------------
	// Output — stdout, file, or both
	// --------------------------------------------------------
	var cores []zapcore.Core

	// Always write to stdout
	stdoutCore := zapcore.NewCore(
		encoder,
		zapcore.AddSync(os.Stdout),
		level,
	)
	cores = append(cores, stdoutCore)

	// Optionally write to rotating log file
	if cfg.Log.Output == "file" || cfg.Log.Output == "both" {
		// Ensure log directory exists
		if err := os.MkdirAll(filepath.Dir(cfg.Log.FilePath), 0755); err != nil {
			return err
		}

		// Lumberjack handles log rotation
		fileWriter := &lumberjack.Logger{
			Filename:   cfg.Log.FilePath,
			MaxSize:    cfg.Log.MaxSizeMB,  // MB before rotation
			MaxBackups: cfg.Log.MaxBackups, // Number of old files to keep
			MaxAge:     cfg.Log.MaxAgeDays, // Days before deletion
			Compress:   true,               // gzip old log files
		}

		fileCore := zapcore.NewCore(
			zapcore.NewJSONEncoder(encoderCfg), // Always JSON in file
			zapcore.AddSync(fileWriter),
			level,
		)
		cores = append(cores, fileCore)
	}

	// --------------------------------------------------------
	// Build logger
	// --------------------------------------------------------
	core := zapcore.NewTee(cores...) // Write to all outputs simultaneously

	options := []zap.Option{
		zap.AddCaller(), // Include file:line in logs
		zap.AddCallerSkip(0),
		zap.AddStacktrace(zap.ErrorLevel), // Stack trace for errors
	}

	if !cfg.IsProd() {
		options = append(options, zap.Development()) // Panic on DPanic in dev
	}

	Log = zap.New(core, options...)
	SugaredLog = Log.Sugar()

	Log.Info("✅ Logger initialized",
		zap.String("level", level.String()),
		zap.String("format", cfg.Log.Format),
		zap.String("output", cfg.Log.Output),
		zap.String("env", cfg.App.Env),
	)

	return nil
}

// ============================================================
//  Convenience wrappers — use these throughout the app
// ============================================================

func Info(msg string, fields ...zap.Field) {
	Log.Info(msg, fields...)
}

func Debug(msg string, fields ...zap.Field) {
	Log.Debug(msg, fields...)
}

func Warn(msg string, fields ...zap.Field) {
	Log.Warn(msg, fields...)
}

func Error(msg string, fields ...zap.Field) {
	Log.Error(msg, fields...)
}

func Fatal(msg string, fields ...zap.Field) {
	Log.Fatal(msg, fields...)
}

// ============================================================
//  Request Logger — attach request context to log entries
// ============================================================

// WithRequestID returns a logger with the request ID attached.
// Use this in HTTP handlers so every log line has the request ID.
//
// Usage:
//
//	log := logger.WithRequestID(c.GetString("requestID"))
//	log.Info("Processing document upload")
func WithRequestID(requestID string) *zap.Logger {
	return Log.With(zap.String("request_id", requestID))
}

// WithUserID returns a logger with user ID attached
func WithUserID(userID string) *zap.Logger {
	return Log.With(zap.String("user_id", userID))
}

// WithFields returns a logger with multiple fields attached
func WithFields(fields ...zap.Field) *zap.Logger {
	return Log.With(fields...)
}

// ============================================================
//  Sync — call on application shutdown
// ============================================================

// Sync flushes any buffered log entries.
// Call this with defer in main():
//
//	defer logger.Sync()
func Sync() {
	if Log != nil {
		_ = Log.Sync()
	}
}

// ============================================================
//  Field helpers — shorthand for common log fields
// ============================================================

func Err(err error) zap.Field                   { return zap.Error(err) }
func Str(key, val string) zap.Field             { return zap.String(key, val) }
func Int(key string, val int) zap.Field         { return zap.Int(key, val) }
func Any(key string, val interface{}) zap.Field { return zap.Any(key, val) }
