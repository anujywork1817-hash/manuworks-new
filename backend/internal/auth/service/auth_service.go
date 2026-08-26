package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"github.com/yourusername/docassist/config"
	"github.com/yourusername/docassist/internal/auth/model"
	"github.com/yourusername/docassist/internal/auth/repository"
	"github.com/yourusername/docassist/pkg/logger"
	"github.com/yourusername/docassist/pkg/middleware"
)

// ─── Sentinel errors ──────────────────────────────────────────────────────────

var (
	ErrInvalidCredentials = errors.New("invalid email or password")
	ErrAccountLocked      = errors.New("account is temporarily locked due to too many failed attempts")
	ErrAccountInactive    = errors.New("account is inactive or suspended")
	ErrEmailTaken         = errors.New("an account with this email already exists")
	ErrInvalidToken       = errors.New("invalid or expired token")
	ErrTokenRevoked       = errors.New("token has been revoked")
	ErrWeakPassword       = errors.New("password does not meet requirements")
	ErrSamePassword       = errors.New("new password must be different from the current password")
)

// maxFailedAttempts before an account is temporarily locked.
const maxFailedAttempts = 5

// lockDuration is how long an account stays locked after too many failures.
const lockDuration = 15 * time.Minute

// ─── Interface ────────────────────────────────────────────────────────────────

type AuthService interface {
	Register(ctx context.Context, req *model.RegisterRequest, ipAddress string) (*model.AuthResponse, error)
	Login(ctx context.Context, req *model.LoginRequest, ipAddress, userAgent string) (*model.AuthResponse, error)
	RefreshToken(ctx context.Context, rawRefreshToken string, ipAddress string) (*model.AuthResponse, error)
	Logout(ctx context.Context, rawRefreshToken string) error
	LogoutAll(ctx context.Context, userID uuid.UUID) error
	ForgotPassword(ctx context.Context, req *model.ForgotPasswordRequest) error
	ResetPassword(ctx context.Context, req *model.ResetPasswordRequest) error
	ChangePassword(ctx context.Context, userID uuid.UUID, req *model.ChangePasswordRequest) error
	GetProfile(ctx context.Context, userID uuid.UUID) (*model.UserInfo, error)
	UpdateProfile(ctx context.Context, userID uuid.UUID, req *model.UpdateProfileRequest) (*model.UserInfo, error)
}

// ─── Implementation ───────────────────────────────────────────────────────────

type authService struct {
	repo   repository.AuthRepository
	cfg    *config.Config
	mailer Mailer // interface — swap real SMTP for mock in tests
}

// Mailer is a minimal interface so the service doesn't depend on a concrete SMTP package.
type Mailer interface {
	SendPasswordReset(toEmail, toName, resetURL string) error
}

func New(repo repository.AuthRepository, cfg *config.Config, mailer Mailer) AuthService {
	return &authService{repo: repo, cfg: cfg, mailer: mailer}
}

// ─── Register ─────────────────────────────────────────────────────────────────

func (s *authService) Register(ctx context.Context, req *model.RegisterRequest, ipAddress string) (*model.AuthResponse, error) {
	// 1. Check email uniqueness
	existing, err := s.repo.GetUserByEmail(ctx, req.Email)
	if err != nil && !errors.Is(err, repository.ErrNotFound) {
		return nil, fmt.Errorf("register: check email: %w", err)
	}
	if existing != nil {
		return nil, ErrEmailTaken
	}

	// 2. Hash password
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), s.cfg.Security.BcryptCost)
	if err != nil {
		return nil, fmt.Errorf("register: hash password: %w", err)
	}

	// 3. Fetch default "user" role
	role, err := s.repo.GetRoleByName(ctx, model.RoleUser)
	if err != nil {
		return nil, fmt.Errorf("register: get role: %w", err)
	}

	// 4. Create user
	user := &model.User{
		RoleID:       role.ID,
		Email:        req.Email,
		PasswordHash: string(hash),
		FirstName:    req.FirstName,
		LastName:     req.LastName,
		Status:       model.UserStatusActive,
	}
	if err = s.repo.CreateUser(ctx, user); err != nil {
		return nil, fmt.Errorf("register: create user: %w", err)
	}
	user.Role = *role

	logger.Info("user registered", logger.Str("user_id", user.ID.String()), logger.Str("email", user.Email))

	// 5. Issue tokens immediately so user lands logged in after registration
	return s.issueTokenPair(ctx, user, ipAddress, "")
}

// ─── Login ────────────────────────────────────────────────────────────────────

func (s *authService) Login(ctx context.Context, req *model.LoginRequest, ipAddress, userAgent string) (*model.AuthResponse, error) {
	// 1. Look up user — use generic error to prevent email enumeration
	user, err := s.repo.GetUserByEmail(ctx, req.Email)
	if err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			return nil, ErrInvalidCredentials
		}
		return nil, fmt.Errorf("login: get user: %w", err)
	}

	// 2. Check account status
	if user.Status != model.UserStatusActive {
		return nil, ErrAccountInactive
	}

	// 3. Check lockout
	if user.IsLocked() {
		return nil, ErrAccountLocked
	}

	// 4. Verify password
	if err = bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		// Track failed attempt; lock after threshold
		_ = s.repo.IncrementFailedLogins(ctx, user.ID.String())
		if user.FailedLoginCount+1 >= maxFailedAttempts {
			lockUntil := time.Now().Add(lockDuration)
			_ = s.repo.LockAccount(ctx, user.ID.String(), lockUntil)
			logger.Warn("account locked", logger.Str("user_id", user.ID.String()))
			return nil, ErrAccountLocked
		}
		return nil, ErrInvalidCredentials
	}

	// 5. Reset failure counter on successful password check
	_ = s.repo.ResetFailedLogins(ctx, user.ID.String())
	_ = s.repo.UpdateLastLogin(ctx, user.ID.String(), ipAddress)
	logger.Info("user logged in",
		logger.Str("user_id", user.ID.String()),
		logger.Str("ip", ipAddress),
	)

	return s.issueTokenPair(ctx, user, ipAddress, userAgent)
}

// ─── Refresh Token ────────────────────────────────────────────────────────────

func (s *authService) RefreshToken(ctx context.Context, rawRefreshToken string, ipAddress string) (*model.AuthResponse, error) {
	// 1. Validate the JWT signature and extract claims
	claims, err := middleware.ParseRefreshToken(rawRefreshToken, s.cfg)
	if err != nil {
		return nil, ErrInvalidToken
	}

	// 2. Hash the raw token to look it up in the DB
	tokenHash := hashToken(rawRefreshToken)
	stored, err := s.repo.GetRefreshToken(ctx, tokenHash)
	if err != nil {
		return nil, ErrInvalidToken
	}

	// 3. Check it hasn't been revoked or expired
	if !stored.IsValid() {
		return nil, ErrTokenRevoked
	}

	// 4. Verify the token ID in the JWT matches the DB row (prevents token swapping)
	if stored.ID.String() != claims.TokenID {
		// Possible token reuse attack — revoke everything for this user
		_ = s.repo.RevokeAllUserTokens(ctx, stored.UserID.String())
		logger.Warn("refresh token ID mismatch — possible reuse attack",
			logger.Str("user_id", stored.UserID.String()),
		)
		return nil, ErrTokenRevoked
	}

	// 5. Revoke the used token (rotation: one-time use)
	if err = s.repo.RevokeRefreshToken(ctx, tokenHash); err != nil {
		return nil, fmt.Errorf("refresh: revoke old token: %w", err)
	}

	// 6. Load the user for the new token pair
	user, err := s.repo.GetUserByID(ctx, stored.UserID.String())
	if err != nil {
		return nil, fmt.Errorf("refresh: get user: %w", err)
	}
	if user.Status != model.UserStatusActive {
		return nil, ErrAccountInactive
	}

	return s.issueTokenPair(ctx, user, ipAddress, "")
}

// ─── Logout ───────────────────────────────────────────────────────────────────

func (s *authService) Logout(ctx context.Context, rawRefreshToken string) error {
	tokenHash := hashToken(rawRefreshToken)
	if err := s.repo.RevokeRefreshToken(ctx, tokenHash); err != nil && !errors.Is(err, repository.ErrNotFound) {
		return fmt.Errorf("logout: revoke token: %w", err)
	}
	return nil
}

func (s *authService) LogoutAll(ctx context.Context, userID uuid.UUID) error {
	return s.repo.RevokeAllUserTokens(ctx, userID.String())
}

// ─── Forgot / Reset Password ──────────────────────────────────────────────────

func (s *authService) ForgotPassword(ctx context.Context, req *model.ForgotPasswordRequest) error {
	user, err := s.repo.GetUserByEmail(ctx, req.Email)
	if err != nil {
		// Always return nil — never reveal whether the email exists
		return nil
	}

	// Invalidate any existing reset tokens for this user
	// reset token created below

	// Generate a cryptographically random 32-byte token
	rawToken, err := generateSecureToken(32)
	if err != nil {
		return fmt.Errorf("forgot password: generate token: %w", err)
	}

	resetToken := &model.PasswordResetToken{
		UserID:    user.ID,
		TokenHash: hashToken(rawToken),
		ExpiresAt: time.Now().Add(s.cfg.Security.PasswordResetExpiry),
	}
	if err = s.repo.CreatePasswordResetToken(ctx, resetToken); err != nil {
		return fmt.Errorf("forgot password: save token: %w", err)
	}

	// Build reset URL and fire email asynchronously
	resetURL := fmt.Sprintf("%s/reset-password?token=%s", s.cfg.App.BaseURL, rawToken)
	go func() {
		if mailErr := s.mailer.SendPasswordReset(user.Email, user.FullName(), resetURL); mailErr != nil {
			logger.Error("forgot password: send email failed",
				logger.Err(mailErr),
				logger.Str("user_id", user.ID.String()),
			)
		}
	}()

	logger.Info("password reset requested", logger.Str("user_id", user.ID.String()))
	return nil
}

func (s *authService) ResetPassword(ctx context.Context, req *model.ResetPasswordRequest) error {
	tokenHash := hashToken(req.Token)
	stored, err := s.repo.GetPasswordResetToken(ctx, tokenHash)
	if err != nil {
		return ErrInvalidToken
	}
	if !stored.IsValid() {
		return ErrInvalidToken
	}

	// Hash the new password
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), s.cfg.Security.BcryptCost)
	if err != nil {
		return fmt.Errorf("reset password: hash: %w", err)
	}

	// Update password and record the change time
	now := time.Now()
	user := stored.User
	user.PasswordHash = string(hash)
	user.PasswordChangedAt = &now
	if err = s.repo.UpdateUser(ctx, &user); err != nil {
		return fmt.Errorf("reset password: update user: %w", err)
	}

	// Mark token as used and revoke all active sessions
	_ = s.repo.MarkPasswordResetTokenUsed(ctx, tokenHash)
	_ = s.repo.RevokeAllUserTokens(ctx, user.ID.String())

	logger.Info("password reset completed", logger.Str("user_id", user.ID.String()))
	return nil
}

// ─── Change Password ──────────────────────────────────────────────────────────

func (s *authService) ChangePassword(ctx context.Context, userID uuid.UUID, req *model.ChangePasswordRequest) error {
	user, err := s.repo.GetUserByID(ctx, userID.String())
	if err != nil {
		return fmt.Errorf("change password: get user: %w", err)
	}

	// Verify current password
	if err = bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.CurrentPassword)); err != nil {
		return ErrInvalidCredentials
	}

	// Prevent reuse of the same password
	if err = bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.NewPassword)); err == nil {
		return ErrSamePassword
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), s.cfg.Security.BcryptCost)
	if err != nil {
		return fmt.Errorf("change password: hash: %w", err)
	}

	now := time.Now()
	user.PasswordHash = string(hash)
	user.PasswordChangedAt = &now
	if err = s.repo.UpdateUser(ctx, user); err != nil {
		return fmt.Errorf("change password: update: %w", err)
	}

	// Revoke all other sessions — force re-login everywhere
	_ = s.repo.RevokeAllUserTokens(ctx, userID.String())

	logger.Info("password changed", logger.Str("user_id", userID.String()))
	return nil
}

// ─── Profile ──────────────────────────────────────────────────────────────────

func (s *authService) GetProfile(ctx context.Context, userID uuid.UUID) (*model.UserInfo, error) {
	user, err := s.repo.GetUserByID(ctx, userID.String())
	if err != nil {
		return nil, fmt.Errorf("get profile: %w", err)
	}
	info := model.ToUserInfo(user)
	return &info, nil
}

func (s *authService) UpdateProfile(ctx context.Context, userID uuid.UUID, req *model.UpdateProfileRequest) (*model.UserInfo, error) {
	user, err := s.repo.GetUserByID(ctx, userID.String())
	if err != nil {
		return nil, fmt.Errorf("update profile: get user: %w", err)
	}

	if req.FirstName != nil {
		user.FirstName = *req.FirstName
	}
	if req.LastName != nil {
		user.LastName = *req.LastName
	}
	if req.AvatarURL != nil {
		user.AvatarURL = req.AvatarURL
	}

	if err = s.repo.UpdateUser(ctx, user); err != nil {
		return nil, fmt.Errorf("update profile: save: %w", err)
	}

	info := model.ToUserInfo(user)
	return &info, nil
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// issueTokenPair generates a new access + refresh token pair, persists the
// refresh token hash, and returns the full AuthResponse.
func (s *authService) issueTokenPair(ctx context.Context, user *model.User, ipAddress, userAgent string) (*model.AuthResponse, error) {
	// Generate a UUID that becomes the refresh token's DB primary key
	// and is embedded in the JWT claims — used to detect token reuse.
	tokenID := uuid.New()

	accessToken, err := middleware.GenerateAccessToken(user.ID.String(), user.Email, user.Role.Name, s.cfg)
	if err != nil {
		return nil, fmt.Errorf("issue tokens: access: %w", err)
	}

	rawRefresh, err := middleware.GenerateRefreshToken(user.ID.String(), tokenID.String(), s.cfg)
	if err != nil {
		return nil, fmt.Errorf("issue tokens: refresh: %w", err)
	}

	// Store the hashed refresh token — never store raw tokens
	ip := &ipAddress
	ua := &userAgent
	dbToken := &model.RefreshToken{
		ID:        tokenID,
		UserID:    user.ID,
		TokenHash: hashToken(rawRefresh),
		IPAddress: ip,
		UserAgent: ua,
		ExpiresAt: time.Now().Add(s.cfg.JWT.RefreshExpiry),
	}
	if err = s.repo.CreateRefreshToken(ctx, dbToken); err != nil {
		return nil, fmt.Errorf("issue tokens: save refresh token: %w", err)
	}

	expiresIn := int64(s.cfg.JWT.AccessExpiry.Seconds())
	info := model.ToUserInfo(user)

	return &model.AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: rawRefresh,
		ExpiresIn:    expiresIn,
		User:         info,
	}, nil
}

// hashToken returns the SHA-256 hex digest of a raw token string.
// We store hashes, never raw tokens, so a DB breach can't be used to hijack sessions.
func hashToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

// generateSecureToken returns a cryptographically random hex string of byteLen bytes.
func generateSecureToken(byteLen int) (string, error) {
	b := make([]byte, byteLen)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}









