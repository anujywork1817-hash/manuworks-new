package repository

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/yourusername/docassist/internal/matter/model"
)

var ErrMatterNotFound = errors.New("matter not found")

type MatterRepository interface {
	Create(ctx context.Context, m *model.Matter) error
	GetByIDAndUserID(ctx context.Context, id, userID uuid.UUID) (*model.Matter, error)
	List(ctx context.Context, userID uuid.UUID) ([]*model.Matter, error)
	Update(ctx context.Context, m *model.Matter) error
	Delete(ctx context.Context, id, userID uuid.UUID) error
	AddDocument(ctx context.Context, matterID, documentID uuid.UUID) error
	RemoveDocument(ctx context.Context, matterID, documentID uuid.UUID) error
	GetDocumentIDs(ctx context.Context, matterID uuid.UUID) ([]uuid.UUID, error)
	CountDocuments(ctx context.Context, matterID uuid.UUID) (int64, error)
}

type matterRepository struct{ db *gorm.DB }

func NewMatterRepository(db *gorm.DB) MatterRepository {
	return &matterRepository{db: db}
}

func (r *matterRepository) Create(ctx context.Context, m *model.Matter) error {
	return r.db.WithContext(ctx).Create(m).Error
}

func (r *matterRepository) GetByIDAndUserID(ctx context.Context, id, userID uuid.UUID) (*model.Matter, error) {
	var m model.Matter
	err := r.db.WithContext(ctx).Where("id = ? AND user_id = ?", id, userID).First(&m).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrMatterNotFound
	}
	return &m, err
}

func (r *matterRepository) List(ctx context.Context, userID uuid.UUID) ([]*model.Matter, error) {
	var matters []*model.Matter
	err := r.db.WithContext(ctx).
		Where("user_id = ?", userID).
		Order("created_at DESC").
		Find(&matters).Error
	return matters, err
}

func (r *matterRepository) Update(ctx context.Context, m *model.Matter) error {
	return r.db.WithContext(ctx).Save(m).Error
}

func (r *matterRepository) Delete(ctx context.Context, id, userID uuid.UUID) error {
	return r.db.WithContext(ctx).
		Where("id = ? AND user_id = ?", id, userID).
		Delete(&model.Matter{}).Error
}

func (r *matterRepository) AddDocument(ctx context.Context, matterID, documentID uuid.UUID) error {
	md := model.MatterDocument{MatterID: matterID, DocumentID: documentID}
	return r.db.WithContext(ctx).
		Where("matter_id = ? AND document_id = ?", matterID, documentID).
		FirstOrCreate(&md).Error
}

func (r *matterRepository) RemoveDocument(ctx context.Context, matterID, documentID uuid.UUID) error {
	return r.db.WithContext(ctx).
		Where("matter_id = ? AND document_id = ?", matterID, documentID).
		Delete(&model.MatterDocument{}).Error
}

func (r *matterRepository) GetDocumentIDs(ctx context.Context, matterID uuid.UUID) ([]uuid.UUID, error) {
	var rows []model.MatterDocument
	err := r.db.WithContext(ctx).Where("matter_id = ?", matterID).Find(&rows).Error
	if err != nil {
		return nil, err
	}
	ids := make([]uuid.UUID, len(rows))
	for i, row := range rows {
		ids[i] = row.DocumentID
	}
	return ids, nil
}

func (r *matterRepository) CountDocuments(ctx context.Context, matterID uuid.UUID) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&model.MatterDocument{}).
		Where("matter_id = ?", matterID).Count(&count).Error
	return count, err
}
