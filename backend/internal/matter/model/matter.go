package model

import (
	"time"

	"github.com/google/uuid"
)

type Matter struct {
	ID          uuid.UUID `gorm:"type:uuid;primaryKey" json:"id"`
	UserID      uuid.UUID `gorm:"type:uuid;not null;index" json:"user_id"`
	Title       string    `gorm:"type:varchar(500);not null" json:"title"`
	MatterNo    string    `gorm:"type:varchar(100)" json:"matter_no"`
	Client      string    `gorm:"type:varchar(255)" json:"client"`
	Court       string    `gorm:"type:varchar(255)" json:"court"`
	Status      string    `gorm:"type:varchar(20);default:'active'" json:"status"`
	Description string    `gorm:"type:text" json:"description"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

func (Matter) TableName() string { return "matters" }

type MatterDocument struct {
	MatterID   uuid.UUID `gorm:"type:uuid;primaryKey" json:"matter_id"`
	DocumentID uuid.UUID `gorm:"type:uuid;primaryKey" json:"document_id"`
	AddedAt    time.Time `gorm:"autoCreateTime" json:"added_at"`
}

func (MatterDocument) TableName() string { return "matter_documents" }
