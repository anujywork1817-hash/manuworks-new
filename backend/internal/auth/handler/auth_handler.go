package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/yourusername/docassist/internal/auth/model"
	"github.com/yourusername/docassist/internal/auth/service"
	"github.com/yourusername/docassist/pkg/logger"
	"github.com/yourusername/docassist/pkg/middleware"
)

// ─── Handler ──────────────────────────────────────────────────────────────────

type AuthHandler struct {
	svc service.AuthService
}

func New(svc service.AuthService) *AuthHandler {
	return &AuthHandler{svc: svc}
}

// ─── Register ─────────────────────────────────────────────────────────────────

// Register godoc
// @Summary      Register a new user
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body model.RegisterRequest true "Registration payload"
// @Success      201  {object} Response{data=model.AuthResponse}
// @Failure      400  {object} ErrorResponse
// @Failure      409  {object} ErrorResponse
// @Router       /auth/register [post]
func (h *AuthHandler) Register(c *gin.Context) {
	var req model.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondValidationError(c, err)
		return
	}

	ip := c.ClientIP()
	resp, err := h.svc.Register(c.Request.Context(), &req, ip)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrEmailTaken):
			respondError(c, http.StatusConflict, "EMAIL_TAKEN", err.Error())
		default:
			respondInternalError(c, err)
		}
		return
	}

	respond(c, http.StatusCreated, "Registration successful", resp)
}

// ─── Login ────────────────────────────────────────────────────────────────────

// Login godoc
// @Summary      Login with email and password
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body model.LoginRequest true "Login credentials"
// @Success      200  {object} Response{data=model.AuthResponse}
// @Failure      400  {object} ErrorResponse
// @Failure      401  {object} ErrorResponse
// @Failure      423  {object} ErrorResponse "Account locked"
// @Router       /auth/login [post]
func (h *AuthHandler) Login(c *gin.Context) {
	var req model.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondValidationError(c, err)
		return
	}

	ip := c.ClientIP()
	ua := c.Request.UserAgent()

	resp, err := h.svc.Login(c.Request.Context(), &req, ip, ua)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrInvalidCredentials):
			respondError(c, http.StatusUnauthorized, "INVALID_CREDENTIALS", err.Error())
		case errors.Is(err, service.ErrAccountLocked):
			respondError(c, http.StatusLocked, "ACCOUNT_LOCKED", err.Error())
		case errors.Is(err, service.ErrAccountInactive):
			respondError(c, http.StatusForbidden, "ACCOUNT_INACTIVE", err.Error())
		default:
			respondInternalError(c, err)
		}
		return
	}

	respond(c, http.StatusOK, "Login successful", resp)
}

// ─── Refresh Token ────────────────────────────────────────────────────────────

// RefreshToken godoc
// @Summary      Refresh access token
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body model.RefreshTokenRequest true "Refresh token"
// @Success      200  {object} Response{data=model.AuthResponse}
// @Failure      401  {object} ErrorResponse
// @Router       /auth/refresh [post]
func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req model.RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondValidationError(c, err)
		return
	}

	ip := c.ClientIP()
	resp, err := h.svc.RefreshToken(c.Request.Context(), req.RefreshToken, ip)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrInvalidToken), errors.Is(err, service.ErrTokenRevoked):
			respondError(c, http.StatusUnauthorized, "INVALID_TOKEN", err.Error())
		default:
			respondInternalError(c, err)
		}
		return
	}

	respond(c, http.StatusOK, "Token refreshed", resp)
}

// ─── Logout ───────────────────────────────────────────────────────────────────

// Logout godoc
// @Summary      Logout current session
// @Tags         auth
// @Security     BearerAuth
// @Accept       json
// @Produce      json
// @Param        body body model.RefreshTokenRequest true "Refresh token to revoke"
// @Success      200  {object} Response
// @Failure      401  {object} ErrorResponse
// @Router       /auth/logout [post]
func (h *AuthHandler) Logout(c *gin.Context) {
	var req model.RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondValidationError(c, err)
		return
	}

	if err := h.svc.Logout(c.Request.Context(), req.RefreshToken); err != nil {
		respondInternalError(c, err)
		return
	}

	respond(c, http.StatusOK, "Logged out successfully", nil)
}

// LogoutAll godoc
// @Summary      Logout all sessions for the current user
// @Tags         auth
// @Security     BearerAuth
// @Produce      json
// @Success      200  {object} Response
// @Failure      401  {object} ErrorResponse
// @Router       /auth/logout-all [post]
func (h *AuthHandler) LogoutAll(c *gin.Context) {
	userID, err := getUserID(c)
	if err != nil {
		respondError(c, http.StatusUnauthorized, "UNAUTHORIZED", "invalid user context")
		return
	}

	if err := h.svc.LogoutAll(c.Request.Context(), userID); err != nil {
		respondInternalError(c, err)
		return
	}

	respond(c, http.StatusOK, "All sessions revoked", nil)
}

// ─── Forgot / Reset Password ──────────────────────────────────────────────────

// ForgotPassword godoc
// @Summary      Request a password reset email
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body model.ForgotPasswordRequest true "Email address"
// @Success      200  {object} Response
// @Router       /auth/forgot-password [post]
func (h *AuthHandler) ForgotPassword(c *gin.Context) {
	var req model.ForgotPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondValidationError(c, err)
		return
	}

	// Service always returns nil to prevent email enumeration —
	// we always respond 200 regardless of whether the email exists.
	_ = h.svc.ForgotPassword(c.Request.Context(), &req)

	respond(c, http.StatusOK, "If that email is registered, a reset link has been sent", nil)
}

// ResetPassword godoc
// @Summary      Reset password using a token from email
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body model.ResetPasswordRequest true "Reset token and new password"
// @Success      200  {object} Response
// @Failure      400  {object} ErrorResponse
// @Failure      401  {object} ErrorResponse
// @Router       /auth/reset-password [post]
func (h *AuthHandler) ResetPassword(c *gin.Context) {
	var req model.ResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondValidationError(c, err)
		return
	}

	if err := h.svc.ResetPassword(c.Request.Context(), &req); err != nil {
		switch {
		case errors.Is(err, service.ErrInvalidToken):
			respondError(c, http.StatusUnauthorized, "INVALID_TOKEN", err.Error())
		default:
			respondInternalError(c, err)
		}
		return
	}

	respond(c, http.StatusOK, "Password reset successfully. Please log in.", nil)
}

// ─── Change Password ──────────────────────────────────────────────────────────

// ChangePassword godoc
// @Summary      Change password for the logged-in user
// @Tags         auth
// @Security     BearerAuth
// @Accept       json
// @Produce      json
// @Param        body body model.ChangePasswordRequest true "Current and new password"
// @Success      200  {object} Response
// @Failure      400  {object} ErrorResponse
// @Failure      401  {object} ErrorResponse
// @Router       /auth/change-password [post]
func (h *AuthHandler) ChangePassword(c *gin.Context) {
	userID, err := getUserID(c)
	if err != nil {
		respondError(c, http.StatusUnauthorized, "UNAUTHORIZED", "invalid user context")
		return
	}

	var req model.ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondValidationError(c, err)
		return
	}

	if err := h.svc.ChangePassword(c.Request.Context(), userID, &req); err != nil {
		switch {
		case errors.Is(err, service.ErrInvalidCredentials):
			respondError(c, http.StatusUnauthorized, "INVALID_CREDENTIALS", "current password is incorrect")
		case errors.Is(err, service.ErrSamePassword):
			respondError(c, http.StatusBadRequest, "SAME_PASSWORD", err.Error())
		default:
			respondInternalError(c, err)
		}
		return
	}

	respond(c, http.StatusOK, "Password changed successfully", nil)
}

// ─── Profile ──────────────────────────────────────────────────────────────────

// GetProfile godoc
// @Summary      Get the current user's profile
// @Tags         auth
// @Security     BearerAuth
// @Produce      json
// @Success      200  {object} Response{data=model.UserInfo}
// @Failure      401  {object} ErrorResponse
// @Router       /auth/me [get]
func (h *AuthHandler) GetProfile(c *gin.Context) {
	userID, err := getUserID(c)
	if err != nil {
		respondError(c, http.StatusUnauthorized, "UNAUTHORIZED", "invalid user context")
		return
	}

	profile, err := h.svc.GetProfile(c.Request.Context(), userID)
	if err != nil {
		respondInternalError(c, err)
		return
	}

	respond(c, http.StatusOK, "Profile retrieved", profile)
}

// UpdateProfile godoc
// @Summary      Update the current user's profile
// @Tags         auth
// @Security     BearerAuth
// @Accept       json
// @Produce      json
// @Param        body body model.UpdateProfileRequest true "Profile fields to update"
// @Success      200  {object} Response{data=model.UserInfo}
// @Failure      400  {object} ErrorResponse
// @Failure      401  {object} ErrorResponse
// @Router       /auth/me [patch]
func (h *AuthHandler) UpdateProfile(c *gin.Context) {
	userID, err := getUserID(c)
	if err != nil {
		respondError(c, http.StatusUnauthorized, "UNAUTHORIZED", "invalid user context")
		return
	}

	var req model.UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondValidationError(c, err)
		return
	}

	profile, err := h.svc.UpdateProfile(c.Request.Context(), userID, &req)
	if err != nil {
		respondInternalError(c, err)
		return
	}

	respond(c, http.StatusOK, "Profile updated", profile)
}

// ─── Response helpers ─────────────────────────────────────────────────────────

// Response is the standard envelope for all successful API responses.
type Response struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// ErrorResponse is the standard envelope for all error responses.
type ErrorResponse struct {
	Success bool   `json:"success"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

// ValidationError wraps field-level validation failures.
type ValidationError struct {
	Success bool              `json:"success"`
	Code    string            `json:"code"`
	Message string            `json:"message"`
	Fields  map[string]string `json:"fields"`
}

func respond(c *gin.Context, status int, message string, data interface{}) {
	c.JSON(status, Response{
		Success: true,
		Message: message,
		Data:    data,
	})
}

func respondError(c *gin.Context, status int, code, message string) {
	c.JSON(status, ErrorResponse{
		Success: false,
		Code:    code,
		Message: message,
	})
}

func respondInternalError(c *gin.Context, err error) {
	log := logger.WithRequestID(c.GetString("requestID"))
	log.Error("internal server error", logger.Err(err))
	c.JSON(http.StatusInternalServerError, ErrorResponse{
		Success: false,
		Code:    "INTERNAL_ERROR",
		Message: "An unexpected error occurred. Please try again.",
	})
}

func respondValidationError(c *gin.Context, err error) {
	fields := parseValidationErrors(err)
	c.JSON(http.StatusBadRequest, ValidationError{
		Success: false,
		Code:    "VALIDATION_ERROR",
		Message: "Request validation failed",
		Fields:  fields,
	})
}

// parseValidationErrors converts Gin's binding errors into a
// field → human-readable message map for the client.
func parseValidationErrors(err error) map[string]string {
	fields := make(map[string]string)

	// Try to cast to gin validator errors
	type fieldError interface {
		Field() string
		Tag() string
		Param() string
	}
	type validationErrors interface {
		Error() string
	}

	// Walk the error chain looking for validator.ValidationErrors
	var ve interface{ Error() string } = err
	_ = ve

	// Simple fallback: return the raw error string under "error"
	// Replace with github.com/go-playground/validator binding for richer messages
	fields["error"] = err.Error()
	return fields
}

// ─── Context helpers ──────────────────────────────────────────────────────────

// getUserID extracts the authenticated user's UUID from the Gin context.
// It is set by the AuthRequired middleware in pkg/middleware/jwt.go.
func getUserID(c *gin.Context) (uuid.UUID, error) {
	raw := middleware.GetUserID(c)
	if raw == "" {
		return uuid.Nil, errors.New("user_id not in context")
	}
	return uuid.Parse(raw)
}
