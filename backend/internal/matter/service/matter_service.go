package service

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourusername/docassist/internal/matter/model"
	"github.com/yourusername/docassist/internal/matter/repository"
)

// ─── Request types ────────────────────────────────────────────────────────────

type CreateMatterRequest struct {
	Title       string `json:"title" binding:"required,min=1,max=500"`
	MatterNo    string `json:"matter_no"`
	Client      string `json:"client"`
	Court       string `json:"court"`
	Description string `json:"description"`
}

type UpdateMatterRequest struct {
	Title       *string `json:"title"`
	MatterNo    *string `json:"matter_no"`
	Client      *string `json:"client"`
	Court       *string `json:"court"`
	Status      *string `json:"status"`
	Description *string `json:"description"`
}

// ─── Interface ────────────────────────────────────────────────────────────────

type MatterService interface {
	CreateMatter(ctx context.Context, userID uuid.UUID, req CreateMatterRequest) (*model.Matter, error)
	GetMatter(ctx context.Context, userID, matterID uuid.UUID) (*model.Matter, error)
	ListMatters(ctx context.Context, userID uuid.UUID) ([]*model.Matter, error)
	UpdateMatter(ctx context.Context, userID, matterID uuid.UUID, req UpdateMatterRequest) (*model.Matter, error)
	DeleteMatter(ctx context.Context, userID, matterID uuid.UUID) error
	AddDocument(ctx context.Context, userID, matterID, documentID uuid.UUID) error
	RemoveDocument(ctx context.Context, userID, matterID, documentID uuid.UUID) error
	GetDocumentIDs(ctx context.Context, matterID uuid.UUID) ([]uuid.UUID, error)
	CountDocuments(ctx context.Context, matterID uuid.UUID) (int64, error)
}

// ─── Implementation ───────────────────────────────────────────────────────────

type matterService struct{ repo repository.MatterRepository }

func NewMatterService(repo repository.MatterRepository) MatterService {
	return &matterService{repo: repo}
}

func (s *matterService) CreateMatter(ctx context.Context, userID uuid.UUID, req CreateMatterRequest) (*model.Matter, error) {
	m := &model.Matter{
		ID:          uuid.New(),
		UserID:      userID,
		Title:       req.Title,
		MatterNo:    req.MatterNo,
		Client:      req.Client,
		Court:       req.Court,
		Description: req.Description,
		Status:      "active",
	}
	return m, s.repo.Create(ctx, m)
}

func (s *matterService) GetMatter(ctx context.Context, userID, matterID uuid.UUID) (*model.Matter, error) {
	return s.repo.GetByIDAndUserID(ctx, matterID, userID)
}

func (s *matterService) ListMatters(ctx context.Context, userID uuid.UUID) ([]*model.Matter, error) {
	return s.repo.List(ctx, userID)
}

func (s *matterService) UpdateMatter(ctx context.Context, userID, matterID uuid.UUID, req UpdateMatterRequest) (*model.Matter, error) {
	m, err := s.repo.GetByIDAndUserID(ctx, matterID, userID)
	if err != nil {
		return nil, err
	}
	if req.Title != nil {
		m.Title = *req.Title
	}
	if req.MatterNo != nil {
		m.MatterNo = *req.MatterNo
	}
	if req.Client != nil {
		m.Client = *req.Client
	}
	if req.Court != nil {
		m.Court = *req.Court
	}
	if req.Status != nil {
		m.Status = *req.Status
	}
	if req.Description != nil {
		m.Description = *req.Description
	}
	return m, s.repo.Update(ctx, m)
}

func (s *matterService) DeleteMatter(ctx context.Context, userID, matterID uuid.UUID) error {
	if _, err := s.repo.GetByIDAndUserID(ctx, matterID, userID); err != nil {
		return err
	}
	return s.repo.Delete(ctx, matterID, userID)
}

func (s *matterService) AddDocument(ctx context.Context, userID, matterID, documentID uuid.UUID) error {
	if _, err := s.repo.GetByIDAndUserID(ctx, matterID, userID); err != nil {
		return err
	}
	return s.repo.AddDocument(ctx, matterID, documentID)
}

func (s *matterService) RemoveDocument(ctx context.Context, userID, matterID, documentID uuid.UUID) error {
	if _, err := s.repo.GetByIDAndUserID(ctx, matterID, userID); err != nil {
		return err
	}
	return s.repo.RemoveDocument(ctx, matterID, documentID)
}

func (s *matterService) GetDocumentIDs(ctx context.Context, matterID uuid.UUID) ([]uuid.UUID, error) {
	return s.repo.GetDocumentIDs(ctx, matterID)
}

func (s *matterService) CountDocuments(ctx context.Context, matterID uuid.UUID) (int64, error) {
	return s.repo.CountDocuments(ctx, matterID)
}
