package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"

	"github.com/yourusername/docassist/internal/payment/model"
	"github.com/yourusername/docassist/internal/payment/repository"
	"github.com/yourusername/docassist/pkg/razorpay"
)

var (
	ErrUnknownPlan        = errors.New("unknown plan_id")
	ErrOrderMismatch      = errors.New("order does not belong to this user")
	ErrInvalidSignature   = errors.New("payment signature verification failed")
	ErrOrderAlreadyPaid   = errors.New("order already processed")
)

type PaymentService interface {
	CreateOrder(ctx context.Context, userID uuid.UUID, planID string) (*model.CreateOrderResponse, error)
	VerifyPayment(ctx context.Context, userID uuid.UUID, req *model.VerifyRequest) (*model.VerifyResponse, error)
}

type paymentService struct {
	repo repository.PaymentRepository
	rzp  *razorpay.Client
	keyID string
}

func NewPaymentService(repo repository.PaymentRepository, rzp *razorpay.Client, keyID string) PaymentService {
	return &paymentService{repo: repo, rzp: rzp, keyID: keyID}
}

func (s *paymentService) CreateOrder(ctx context.Context, userID uuid.UUID, planID string) (*model.CreateOrderResponse, error) {
	plan, ok := model.Plans[planID]
	if !ok {
		return nil, ErrUnknownPlan
	}

	receipt := fmt.Sprintf("recharge_%s_%s", userID.String()[:8], planID)
	rzpOrder, err := s.rzp.CreateOrder(plan.AmountPaise, "INR", receipt)
	if err != nil {
		return nil, err
	}

	order := &model.Order{
		UserID:          userID,
		PlanID:          plan.ID,
		RazorpayOrderID: rzpOrder.ID,
		AmountPaise:     plan.AmountPaise,
		Currency:        "INR",
		Credits:         plan.Credits,
		Status:          model.OrderStatusCreated,
	}
	if err := s.repo.CreateOrder(ctx, order); err != nil {
		return nil, err
	}

	return &model.CreateOrderResponse{
		OrderID:  rzpOrder.ID,
		Amount:   plan.AmountPaise,
		Currency: "INR",
		KeyID:    s.keyID,
		PlanID:   plan.ID,
		Credits:  plan.Credits,
	}, nil
}

func (s *paymentService) VerifyPayment(ctx context.Context, userID uuid.UUID, req *model.VerifyRequest) (*model.VerifyResponse, error) {
	order, err := s.repo.GetByRazorpayOrderID(ctx, req.RazorpayOrderID)
	if err != nil {
		return nil, err
	}
	if order.UserID != userID {
		return nil, ErrOrderMismatch
	}
	if order.Status != model.OrderStatusCreated {
		return nil, ErrOrderAlreadyPaid
	}

	if !s.rzp.VerifySignature(req.RazorpayOrderID, req.RazorpayPaymentID, req.RazorpaySignature) {
		return nil, ErrInvalidSignature
	}

	if err := s.repo.MarkPaid(ctx, order.ID, req.RazorpayPaymentID); err != nil {
		return nil, err
	}

	newTotal, err := s.repo.AddCredits(ctx, userID, order.Credits)
	if err != nil {
		return nil, err
	}

	return &model.VerifyResponse{
		CreditsAdded: order.Credits,
		CreditsTotal: newTotal,
	}, nil
}
