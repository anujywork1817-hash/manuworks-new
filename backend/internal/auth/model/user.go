package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// ─── Enums ────────────────────────────────────────────────────────────────────

type UserStatus string
type DocumentStatus string

const (
	UserStatusActive    UserStatus = "active"
	UserStatusInactive  UserStatus = "inactive"
	UserStatusSuspended UserStatus = "suspended"

	RoleAdmin = "admin"
	RoleUser  = "user"
)

// ─── Role ─────────────────────────────────────────────────────────────────────

type Role struct {
	ID          uint           `gorm:"primaryKey;autoIncrement"    json:"id"`
	Name        string         `gorm:"uniqueIndex;not null;size:50" json:"name"`
	Description string         `gorm:"size:255"                     json:"description"`
	Permissions []byte         `gorm:"type:jsonb;default:'{}'"      json:"permissions"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index"                        json:"-"`

	Users []User `gorm:"foreignKey:RoleID" json:"-"`
}

func (Role) TableName() string { return "roles" }

// ─── User ─────────────────────────────────────────────────────────────────────

type User struct {
	ID                uuid.UUID      `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	RoleID            uint           `gorm:"not null;default:2"                              json:"role_id"`
	Email             string         `gorm:"uniqueIndex;not null;size:255"                   json:"email"`
	PasswordHash      string         `gorm:"not null;size:255"                               json:"-"`
	FirstName         string         `gorm:"not null;size:100"                               json:"first_name"`
	LastName          string         `gorm:"not null;size:100"                               json:"last_name"`
	Status            UserStatus     `gorm:"type:user_status;default:'active'"               json:"status"`
	AvatarURL         *string        `gorm:"size:500"                                        json:"avatar_url,omitempty"`
	IsEmailVerified   bool           `gorm:"default:false"                                   json:"is_email_verified"`
	LastLoginAt       *time.Time     `json:"last_login_at,omitempty"`
	LoginCount        int            `gorm:"default:0"                                       json:"login_count"`
	FailedLoginCount  int            `gorm:"default:0"                                       json:"-"`
	LockedUntil       *time.Time     `json:"-"`
	PasswordChangedAt *time.Time     `json:"password_changed_at,omitempty"`
	CreatedAt         time.Time      `json:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at"`
	DeletedAt         gorm.DeletedAt `gorm:"index"                                           json:"-"`

	Role          Role           `gorm:"foreignKey:RoleID"          json:"role,omitempty"`
	RefreshTokens []RefreshToken `gorm:"foreignKey:UserID"          json:"-"`
	Settings      *UserSettings  `gorm:"foreignKey:UserID"          json:"settings,omitempty"`
}

func (User) TableName() string { return "users" }

// FullName returns the user's combined first + last name.
func (u *User) FullName() string {
	return u.FirstName + " " + u.LastName
}

// IsLocked reports whether the account is currently locked out.
func (u *User) IsLocked() bool {
	return u.LockedUntil != nil && u.LockedUntil.After(time.Now())
}

// ─── RefreshToken ─────────────────────────────────────────────────────────────

type RefreshToken struct {
	ID         uuid.UUID  `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID     uuid.UUID  `gorm:"type:uuid;not null;index"                       json:"user_id"`
	TokenHash  string     `gorm:"not null;uniqueIndex;size:255"                  json:"-"`
	DeviceInfo *string    `gorm:"size:500"                                       json:"device_info,omitempty"`
	IPAddress  *string    `gorm:"size:45"                                        json:"ip_address,omitempty"`
	UserAgent  *string    `gorm:"size:500"                                       json:"user_agent,omitempty"`
	ExpiresAt  time.Time  `gorm:"not null"                                       json:"expires_at"`
	LastUsedAt *time.Time `json:"last_used_at,omitempty"`
	RevokedAt  *time.Time `json:"revoked_at,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`

	User User `gorm:"foreignKey:UserID" json:"-"`
}

func (RefreshToken) TableName() string { return "refresh_tokens" }

// IsValid reports whether the token has not expired and has not been revoked.
func (t *RefreshToken) IsValid() bool {
	return t.RevokedAt == nil && t.ExpiresAt.After(time.Now())
}

// ─── PasswordResetToken ───────────────────────────────────────────────────────

type PasswordResetToken struct {
	ID        uuid.UUID  `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID    uuid.UUID  `gorm:"type:uuid;not null;index"                       json:"user_id"`
	TokenHash string     `gorm:"not null;uniqueIndex;size:255"                  json:"-"`
	ExpiresAt time.Time  `gorm:"not null"                                       json:"expires_at"`
	UsedAt    *time.Time `json:"used_at,omitempty"`
	CreatedAt time.Time  `json:"created_at"`

	User User `gorm:"foreignKey:UserID" json:"-"`
}

func (PasswordResetToken) TableName() string { return "password_reset_tokens" }

// IsValid reports whether the reset token has not been used and has not expired.
func (t *PasswordResetToken) IsValid() bool {
	return t.UsedAt == nil && t.ExpiresAt.After(time.Now())
}

// ─── UserSettings ─────────────────────────────────────────────────────────────

type UserSettings struct {
	ID                 uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID             uuid.UUID `gorm:"type:uuid;not null;uniqueIndex"                  json:"user_id"`
	Language           string    `gorm:"size:10;default:'en'"                           json:"language"`
	Timezone           string    `gorm:"size:50;default:'UTC'"                          json:"timezone"`
	Theme              string    `gorm:"size:20;default:'system'"                       json:"theme"`
	EmailNotifications bool      `gorm:"default:true"                                   json:"email_notifications"`
	AIDefaultModel     string    `gorm:"size:50;default:'gemini-1.5-flash'"             json:"ai_default_model"`
	StorageUsedBytes   int64     `gorm:"default:0"                                      json:"storage_used_bytes"`
	StorageLimitBytes  int64     `gorm:"default:5368709120"                             json:"storage_limit_bytes"` // 5 GB
	Credits            int64     `gorm:"default:0"                                      json:"credits"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

func (UserSettings) TableName() string { return "user_settings" }

// ─── Request / Response DTOs ──────────────────────────────────────────────────

type RegisterRequest struct {
	FirstName string `json:"first_name" binding:"required,min=2,max=100"`
	LastName  string `json:"last_name"  binding:"required,min=2,max=100"`
	Email     string `json:"email"      binding:"required,email"`
	Password  string `json:"password"   binding:"required,min=8,max=128"`
}

type LoginRequest struct {
	Email    string `json:"email"    binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

type ForgotPasswordRequest struct {
	Email string `json:"email" binding:"required,email"`
}

type ResetPasswordRequest struct {
	Token    string `json:"token"    binding:"required"`
	Password string `json:"password" binding:"required,min=8,max=128"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password" binding:"required"`
	NewPassword     string `json:"new_password"     binding:"required,min=8,max=128"`
}

type UpdateProfileRequest struct {
	FirstName *string `json:"first_name" binding:"omitempty,min=2,max=100"`
	LastName  *string `json:"last_name"  binding:"omitempty,min=2,max=100"`
	AvatarURL *string `json:"avatar_url" binding:"omitempty,url"`
}

// ─── Auth Response ────────────────────────────────────────────────────────────

type AuthResponse struct {
	AccessToken  string   `json:"access_token"`
	RefreshToken string   `json:"refresh_token"`
	ExpiresIn    int64    `json:"expires_in"` // seconds
	User         UserInfo `json:"user"`
}

type UserInfo struct {
	ID              uuid.UUID  `json:"id"`
	Email           string     `json:"email"`
	FirstName       string     `json:"first_name"`
	LastName        string     `json:"last_name"`
	FullName        string     `json:"full_name"`
	Role            string     `json:"role"`
	AvatarURL       *string    `json:"avatar_url,omitempty"`
	IsEmailVerified bool       `json:"is_email_verified"`
	LastLoginAt     *time.Time `json:"last_login_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	Credits         int64      `json:"credits"`
}

// ToUserInfo converts a User model to a safe, serialisable UserInfo response.
func ToUserInfo(u *User) UserInfo {
	info := UserInfo{
		ID:              u.ID,
		Email:           u.Email,
		FirstName:       u.FirstName,
		LastName:        u.LastName,
		FullName:        u.FullName(),
		AvatarURL:       u.AvatarURL,
		IsEmailVerified: u.IsEmailVerified,
		LastLoginAt:     u.LastLoginAt,
		CreatedAt:       u.CreatedAt,
	}
	if u.Role.Name != "" {
		info.Role = u.Role.Name
	}
	if u.Settings != nil {
		info.Credits = u.Settings.Credits
	}
	return info
}
