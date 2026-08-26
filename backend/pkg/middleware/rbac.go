package middleware

import (
	"net/http"

	"github.com/yourusername/docassist/pkg/logger"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// ============================================================
//  Role Constants
// ============================================================

const (
	RoleAdmin = "admin"
	RoleUser  = "user"
)

// ============================================================
//  RBAC Middleware
// ============================================================

// RequireRole returns a Gin middleware that only allows users
// with one of the specified roles to proceed.
//
// Usage — admin only:
//
//	adminRoutes.Use(middleware.AuthRequired(cfg), middleware.RequireRole(middleware.RoleAdmin))
//
// Usage — multiple roles allowed:
//
//	routes.Use(middleware.RequireRole(middleware.RoleAdmin, middleware.RoleUser))
func RequireRole(allowedRoles ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		userRole := GetUserRole(c)
		userID := GetUserID(c)

		// No role in context means AuthRequired was not applied first
		if userRole == "" {
			logger.Warn("RBAC check failed: no role in context",
				zap.String("request_id", GetRequestID(c)),
				zap.String("path", c.FullPath()),
			)
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "Authentication required",
			})
			return
		}

		// Check if user's role is in the allowed list
		for _, role := range allowedRoles {
			if userRole == role {
				c.Next()
				return
			}
		}

		// Role not allowed
		logger.Warn("RBAC check failed: insufficient role",
			zap.String("user_id", userID),
			zap.String("user_role", userRole),
			zap.Strings("required_roles", allowedRoles),
			zap.String("path", c.FullPath()),
			zap.String("request_id", GetRequestID(c)),
		)

		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
			"success": false,
			"error":   "You do not have permission to access this resource",
		})
	}
}

// RequireAdmin is a shorthand for RequireRole(RoleAdmin)
func RequireAdmin() gin.HandlerFunc {
	return RequireRole(RoleAdmin)
}

// ============================================================
//  Resource Ownership Middleware
// ============================================================

// RequireOwnerOrAdmin ensures a user can only access their own
// resources unless they are an admin.
//
// The ownerID parameter is a function that extracts the owner's
// user ID from the request (e.g. from a URL param or DB lookup).
//
// Usage:
//
//	router.DELETE("/documents/:id", middleware.RequireOwnerOrAdmin(getDocOwner))
func RequireOwnerOrAdmin(getOwnerID func(c *gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := GetUserID(c)
		userRole := GetUserRole(c)

		// Admins can access everything
		if userRole == RoleAdmin {
			c.Next()
			return
		}

		// For regular users, check ownership
		ownerID := getOwnerID(c)
		if ownerID == "" {
			c.AbortWithStatusJSON(http.StatusNotFound, gin.H{
				"success": false,
				"error":   "Resource not found",
			})
			return
		}

		if userID != ownerID {
			logger.Warn("Ownership check failed",
				zap.String("user_id", userID),
				zap.String("owner_id", ownerID),
				zap.String("path", c.FullPath()),
				zap.String("request_id", GetRequestID(c)),
			)
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"success": false,
				"error":   "You do not have permission to access this resource",
			})
			return
		}

		c.Next()
	}
}

// ============================================================
//  Rate Limit by Role
// ============================================================

// RoleBasedRateLimit applies different rate limits based on role.
// Admins get higher limits than regular users.
//
// Usage:
//
//	router.Use(middleware.RoleBasedRateLimit(adminLimit, userLimit))
func RoleBasedRateLimit(adminLimit, userLimit int) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Actual rate limiting logic is in the rate_limit.go middleware.
		// This middleware just sets the limit value in context
		// so the rate limiter can read it.
		role := GetUserRole(c)
		limit := userLimit
		if role == RoleAdmin {
			limit = adminLimit
		}
		c.Set("rate_limit", limit)
		c.Next()
	}
}

// ============================================================
//  Helper — IsAdmin
// ============================================================

// IsAdmin returns true if the current request is from an admin user.
// Use inside handlers when you need conditional logic, not blocking.
//
// Usage:
//
//	if middleware.IsAdmin(c) {
//	    // include sensitive fields in response
//	}
func IsAdmin(c *gin.Context) bool {
	return GetUserRole(c) == RoleAdmin
}
