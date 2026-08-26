package repository

import (
	"context"
	"errors"
	"time"

	"github.com/yourusername/docassist/internal/auth/model"
	"gorm.io/gorm"
)

var (
	ErrNotFound      = errors.New("record not found")
	ErrAlreadyExists = errors.New("record already exists")
)

// AuthRepository defines all database operations for auth
type AuthRepository interface {
	// User operations
	CreateUser(ctx context.Context, user *model.User) error
	GetUserByID(ctx context.Context, id string) (*model.User, error)
	GetUserByEmail(ctx context.Context, email string) (*model.User, error)
	UpdateUser(ctx context.Context, user *model.User) error
	DeleteUser(ctx context.Context, id string) error
	ListUsers(ctx context.Context, page, limit int) ([]*model.User, int64, error)

	// Login tracking
	UpdateLastLogin(ctx context.Context, userID string, ip string) error
	IncrementFailedLogins(ctx context.Context, userID string) error
	ResetFailedLogins(ctx context.Context, userID string) error
	LockAccount(ctx context.Context, userID string, until time.Time) error

	// Refresh tokens
	CreateRefreshToken(ctx context.Context, token *model.RefreshToken) error
	GetRefreshToken(ctx context.Context, tokenHash string) (*model.RefreshToken, error)
	RevokeRefreshToken(ctx context.Context, tokenHash string) error
	RevokeAllUserTokens(ctx context.Context, userID string) error
	DeleteExpiredTokens(ctx context.Context) error

	// Password reset
	CreatePasswordResetToken(ctx context.Context, token *model.PasswordResetToken) error
	GetPasswordResetToken(ctx context.Context, tokenHash string) (*model.PasswordResetToken, error)
	MarkPasswordResetTokenUsed(ctx context.Context, tokenHash string) error

	// Role operations
	GetRoleByName(ctx context.Context, name string) (*model.Role, error)
}

type authRepository struct {
	db *gorm.DB
}

// NewAuthRepository creates a new AuthRepository
func NewAuthRepository(db *gorm.DB) AuthRepository {
	return &authRepository{db: db}
}

// ─── User Operations ──────────────────────────────────────────────────────────

func (r *authRepository) CreateUser(ctx context.Context, user *model.User) error {
	result := r.db.WithContext(ctx).Create(user)
	if result.Error != nil {
		if isDuplicateError(result.Error) {
			return ErrAlreadyExists
		}
		return result.Error
	}
	return nil
}

func (r *authRepository) GetUserByID(ctx context.Context, id string) (*model.User, error) {
	var user model.User
	result := r.db.WithContext(ctx).
		Preload("Role").
		Preload("Settings").
		Where("id = ? AND deleted_at IS NULL", id).
		First(&user)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, ErrNotFound
		}
		return nil, result.Error
	}
	return &user, nil
}

func (r *authRepository) GetUserByEmail(ctx context.Context, email string) (*model.User, error) {
	var user model.User
	result := r.db.WithContext(ctx).
		Preload("Role").
		Preload("Settings").
		Where("email = ? AND deleted_at IS NULL", email).
		First(&user)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, ErrNotFound
		}
		return nil, result.Error
	}
	return &user, nil
}

func (r *authRepository) UpdateUser(ctx context.Context, user *model.User) error {
	return r.db.WithContext(ctx).Save(user).Error
}

func (r *authRepository) DeleteUser(ctx context.Context, id string) error {
	// Soft delete — sets deleted_at timestamp
	result := r.db.WithContext(ctx).
		Model(&model.User{}).
		Where("id = ?", id).
		Update("deleted_at", time.Now())
	if result.RowsAffected == 0 {
		return ErrNotFound
	}
	return result.Error
}

func (r *authRepository) ListUsers(ctx context.Context, page, limit int) ([]*model.User, int64, error) {
	var users []*model.User
	var total int64

	offset := (page - 1) * limit

	r.db.WithContext(ctx).
		Model(&model.User{}).
		Where("deleted_at IS NULL").
		Count(&total)

	result := r.db.WithContext(ctx).
		Preload("Role").
		Where("deleted_at IS NULL").
		Order("created_at DESC").
		Offset(offset).
		Limit(limit).
		Find(&users)

	return users, total, result.Error
}

// ─── Login Tracking ───────────────────────────────────────────────────────────

func (r *authRepository) UpdateLastLogin(ctx context.Context, userID string, ip string) error {
	return r.db.WithContext(ctx).
		Model(&model.User{}).
		Where("id = ?", userID).
		Updates(map[string]interface{}{
			"last_login_at": time.Now(),
			"last_login_ip": ip,
			"failed_logins": 0,
			"locked_until":  nil,
		}).Error
}

func (r *authRepository) IncrementFailedLogins(ctx context.Context, userID string) error {
	return r.db.WithContext(ctx).
		Model(&model.User{}).
		Where("id = ?", userID).
		UpdateColumn("failed_logins", gorm.Expr("failed_logins + 1")).Error
}

func (r *authRepository) ResetFailedLogins(ctx context.Context, userID string) error {
	return r.db.WithContext(ctx).
		Model(&model.User{}).
		Where("id = ?", userID).
		Updates(map[string]interface{}{
			"failed_logins": 0,
			"locked_until":  nil,
		}).Error
}

func (r *authRepository) LockAccount(ctx context.Context, userID string, until time.Time) error {
	return r.db.WithContext(ctx).
		Model(&model.User{}).
		Where("id = ?", userID).
		Update("locked_until", until).Error
}

// ─── Refresh Tokens ───────────────────────────────────────────────────────────

func (r *authRepository) CreateRefreshToken(ctx context.Context, token *model.RefreshToken) error {
	return r.db.WithContext(ctx).Create(token).Error
}

func (r *authRepository) GetRefreshToken(ctx context.Context, tokenHash string) (*model.RefreshToken, error) {
	var token model.RefreshToken
	result := r.db.WithContext(ctx).
		Where("token_hash = ? AND revoked_at IS NULL AND expires_at > ?", tokenHash, time.Now()).
		First(&token)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, ErrNotFound
		}
		return nil, result.Error
	}
	return &token, nil
}

func (r *authRepository) RevokeRefreshToken(ctx context.Context, tokenHash string) error {
	now := time.Now()
	result := r.db.WithContext(ctx).
		Model(&model.RefreshToken{}).
		Where("token_hash = ?", tokenHash).
		Update("revoked_at", now)
	if result.RowsAffected == 0 {
		return ErrNotFound
	}
	return result.Error
}

func (r *authRepository) RevokeAllUserTokens(ctx context.Context, userID string) error {
	now := time.Now()
	return r.db.WithContext(ctx).
		Model(&model.RefreshToken{}).
		Where("user_id = ? AND revoked_at IS NULL", userID).
		Update("revoked_at", now).Error
}

func (r *authRepository) DeleteExpiredTokens(ctx context.Context) error {
	return r.db.WithContext(ctx).
		Where("expires_at < ?", time.Now()).
		Delete(&model.RefreshToken{}).Error
}

// ─── Password Reset ───────────────────────────────────────────────────────────

func (r *authRepository) CreatePasswordResetToken(ctx context.Context, token *model.PasswordResetToken) error {
	// Invalidate any existing unused tokens for this user first
	r.db.WithContext(ctx).
		Model(&model.PasswordResetToken{}).
		Where("user_id = ? AND used_at IS NULL", token.UserID).
		Update("used_at", time.Now())

	return r.db.WithContext(ctx).Create(token).Error
}

func (r *authRepository) GetPasswordResetToken(ctx context.Context, tokenHash string) (*model.PasswordResetToken, error) {
	var token model.PasswordResetToken
	result := r.db.WithContext(ctx).
		Where("token_hash = ? AND used_at IS NULL AND expires_at > ?", tokenHash, time.Now()).
		First(&token)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, ErrNotFound
		}
		return nil, result.Error
	}
	return &token, nil
}

func (r *authRepository) MarkPasswordResetTokenUsed(ctx context.Context, tokenHash string) error {
	now := time.Now()
	result := r.db.WithContext(ctx).
		Model(&model.PasswordResetToken{}).
		Where("token_hash = ?", tokenHash).
		Update("used_at", now)
	if result.RowsAffected == 0 {
		return ErrNotFound
	}
	return result.Error
}

// ─── Role Operations ──────────────────────────────────────────────────────────

func (r *authRepository) GetRoleByName(ctx context.Context, name string) (*model.Role, error) {
	var role model.Role
	result := r.db.WithContext(ctx).
		Where("name = ?", name).
		First(&role)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, ErrNotFound
		}
		return nil, result.Error
	}
	return &role, nil
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func isDuplicateError(err error) bool {
	if err == nil {
		return false
	}
	errStr := err.Error()
	return contains(errStr, "duplicate key") ||
		contains(errStr, "unique constraint") ||
		contains(errStr, "UNIQUE constraint failed")
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr ||
		len(s) > 0 && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
