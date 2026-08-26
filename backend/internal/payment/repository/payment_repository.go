package repository

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"gorm.io/gorm"

	authModel "github.com/yourusername/docassist/internal/auth/model"
	"github.com/yourusername/docassist/internal/payment/model"
)

var ErrOrderNotFound = errors.New("order not found")

type PaymentRepository interface {
	CreateOrder(ctx context.Context, o *model.Order) error
	GetByRazorpayOrderID(ctx context.Context, razorpayOrderID string) (*model.Order, error)
	MarkPaid(ctx context.Context, orderID uuid.UUID, razorpayPaymentID string) error
	AddCredits(ctx context.Context, userID uuid.UUID, amount int64) (int64, error)
}

type paymentRepository struct{ db *gorm.DB }

func NewPaymentRepository(db *gorm.DB) PaymentRepository {
	return &paymentRepository{db: db}
}

func (r *paymentRepository) CreateOrder(ctx context.Context, o *model.Order) error {
	return r.db.WithContext(ctx).Create(o).Error
}

func (r *paymentRepository) GetByRazorpayOrderID(ctx context.Context, razorpayOrderID string) (*model.Order, error) {
	var o model.Order
	err := r.db.WithContext(ctx).Where("razorpay_order_id = ?", razorpayOrderID).First(&o).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrOrderNotFound
	}
	return &o, err
}

func (r *paymentRepository) MarkPaid(ctx context.Context, orderID uuid.UUID, razorpayPaymentID string) error {
	return r.db.WithContext(ctx).Model(&model.Order{}).
		Where("id = ? AND status = ?", orderID, model.OrderStatusCreated).
		Updates(map[string]interface{}{
			"status":              model.OrderStatusPaid,
			"razorpay_payment_id": razorpayPaymentID,
		}).Error
}

// AddCredits increments the user's credit balance atomically and returns the
// new total. It creates the settings row on first use since not every user
// has one yet at registration time.
func (r *paymentRepository) AddCredits(ctx context.Context, userID uuid.UUID, amount int64) (int64, error) {
	var newTotal int64

	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var settings authModel.UserSettings
		err := tx.Where("user_id = ?", userID).First(&settings).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			settings = authModel.UserSettings{UserID: userID, Credits: amount}
			if err := tx.Create(&settings).Error; err != nil {
				return err
			}
			newTotal = settings.Credits
			return nil
		}
		if err != nil {
			return err
		}

		if err := tx.Model(&authModel.UserSettings{}).
			Where("user_id = ?", userID).
			Update("credits", gorm.Expr("credits + ?", amount)).Error; err != nil {
			return err
		}
		newTotal = settings.Credits + amount
		return nil
	})

	return newTotal, err
}
