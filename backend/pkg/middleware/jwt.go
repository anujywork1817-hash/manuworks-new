package middleware

import (
	"net/http"
	"strings"
	"time"

	"github.com/yourusername/docassist/config"
	"github.com/yourusername/docassist/pkg/logger"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

// Context keys — use these to read values set by middleware
const (
	ContextUserID    = "user_id"
	ContextUserEmail = "user_email"
	ContextUserRole  = "user_role"
	ContextRequestID = "request_id"
)

// ============================================================
//  JWT Claims
// ============================================================

// AccessClaims represents the payload inside an access token
type AccessClaims struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

// RefreshClaims represents the payload inside a refresh token
type RefreshClaims struct {
	UserID  string `json:"user_id"`
	TokenID string `json:"token_id"` // Maps to refresh_tokens.id in DB
	jwt.RegisteredClaims
}

// ============================================================
//  Token Generation
// ============================================================

// GenerateAccessToken creates a short-lived JWT access token
func GenerateAccessToken(userID, email, role string, cfg *config.Config) (string, error) {
	now := time.Now()
	claims := AccessClaims{
		UserID: userID,
		Email:  email,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    cfg.JWT.Issuer,
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(cfg.JWT.AccessExpiry)),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(cfg.JWT.AccessSecret))
}

// GenerateRefreshToken creates a long-lived JWT refresh token
func GenerateRefreshToken(userID, tokenID string, cfg *config.Config) (string, error) {
	now := time.Now()
	claims := RefreshClaims{
		UserID:  userID,
		TokenID: tokenID,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    cfg.JWT.Issuer,
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(cfg.JWT.RefreshExpiry)),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(cfg.JWT.RefreshSecret))
}

// ============================================================
//  Token Parsing
// ============================================================

// ParseAccessToken validates and parses an access token string
func ParseAccessToken(tokenStr string, cfg *config.Config) (*AccessClaims, error) {
	token, err := jwt.ParseWithClaims(
		tokenStr,
		&AccessClaims{},
		func(token *jwt.Token) (interface{}, error) {
			// Ensure signing method is HMAC
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return []byte(cfg.JWT.AccessSecret), nil
		},
	)
	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*AccessClaims)
	if !ok || !token.Valid {
		return nil, jwt.ErrTokenInvalidClaims
	}

	return claims, nil
}

// ParseRefreshToken validates and parses a refresh token string
func ParseRefreshToken(tokenStr string, cfg *config.Config) (*RefreshClaims, error) {
	token, err := jwt.ParseWithClaims(
		tokenStr,
		&RefreshClaims{},
		func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return []byte(cfg.JWT.RefreshSecret), nil
		},
	)
	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*RefreshClaims)
	if !ok || !token.Valid {
		return nil, jwt.ErrTokenInvalidClaims
	}

	return claims, nil
}

// ============================================================
//  Gin Middleware
// ============================================================

// AuthRequired is a Gin middleware that validates the JWT access token.
// Attach to any route group that requires authentication.
//
// Usage:
//
//	protected := router.Group("/api/v1")
//	protected.Use(middleware.AuthRequired(cfg))
func AuthRequired(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		// ------------------------------------------------
		// Extract token from Authorization header
		// ------------------------------------------------
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "Authorization header is required",
			})
			return
		}

		// Expected format: "Bearer <token>"
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "Authorization header format must be: Bearer <token>",
			})
			return
		}

		tokenStr := parts[1]

		// ------------------------------------------------
		// Parse and validate token
		// ------------------------------------------------
		claims, err := ParseAccessToken(tokenStr, cfg)
		if err != nil {
			var errMsg string
			switch {
			case strings.Contains(err.Error(), "expired"):
				errMsg = "Token has expired. Please refresh your token."
			case strings.Contains(err.Error(), "signature"):
				errMsg = "Invalid token signature."
			default:
				errMsg = "Invalid token."
			}

			logger.Warn("JWT validation failed",
				zap.String("error", err.Error()),
				zap.String("request_id", c.GetString(ContextRequestID)),
			)

			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   errMsg,
			})
			return
		}

		// ------------------------------------------------
		// Inject claims into request context
		// ------------------------------------------------
		c.Set(ContextUserID, claims.UserID)
		c.Set(ContextUserEmail, claims.Email)
		c.Set(ContextUserRole, claims.Role)

		c.Next()
	}
}

// ============================================================
//  Request ID Middleware
// ============================================================

// RequestID injects a unique request ID into every request context.
// This ID is included in all log lines and API responses for tracing.
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Use existing request ID from header if present (e.g. from a proxy)
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = uuid.New().String()
		}

		c.Set(ContextRequestID, requestID)
		c.Header("X-Request-ID", requestID) // Echo back in response header

		c.Next()
	}
}

// ============================================================
//  Helper functions for handlers
// ============================================================

// GetUserID extracts the authenticated user's ID from context.
// Returns empty string if not authenticated.
func GetUserID(c *gin.Context) string {
	id, _ := c.Get(ContextUserID)
	if id == nil {
		return ""
	}
	return id.(string)
}

// GetUserRole extracts the authenticated user's role from context.
func GetUserRole(c *gin.Context) string {
	role, _ := c.Get(ContextUserRole)
	if role == nil {
		return ""
	}
	return role.(string)
}

// GetUserEmail extracts the authenticated user's email from context.
func GetUserEmail(c *gin.Context) string {
	email, _ := c.Get(ContextUserEmail)
	if email == nil {
		return ""
	}
	return email.(string)
}

// GetRequestID extracts the request ID from context.
func GetRequestID(c *gin.Context) string {
	id, _ := c.Get(ContextRequestID)
	if id == nil {
		return ""
	}
	return id.(string)
}
