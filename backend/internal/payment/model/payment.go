package model

import (
	"time"

	"github.com/google/uuid"
)

// ─── Plans ────────────────────────────────────────────────────────────────────

// Plan is a server-defined recharge plan. Amounts and credits are decided
// here, never trusted from the client, so a tampered request can't buy
// credits below their real price.
type Plan struct {
	ID       string
	Name     string
	Credits  int64
	AmountPaise int64 // Razorpay amounts are always in the smallest currency unit
}

var Plans = map[string]Plan{
	"basic":    {ID: "basic", Name: "Basic", Credits: 2500, AmountPaise: 49900},
	"pro":      {ID: "pro", Name: "Pro", Credits: 7500, AmountPaise: 129900},
	"business": {ID: "business", Name: "Business", Credits: 20000, AmountPaise: 299900},
}

// ─── Order ────────────────────────────────────────────────────────────────────

type OrderStatus string

const (
	OrderStatusCreated OrderStatus = "created"
	OrderStatusPaid     OrderStatus = "paid"
	OrderStatusFailed   OrderStatus = "failed"
)

// Order tracks a Razorpay order from creation through verification, so a
// verify call can be checked against what was actually created server-side
// rather than trusting the client's replayed order/payment IDs blindly.
type Order struct {
	ID              uuid.UUID   `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID          uuid.UUID   `gorm:"type:uuid;not null;index"                       json:"user_id"`
	PlanID          string      `gorm:"size:50;not null"                               json:"plan_id"`
	RazorpayOrderID string      `gorm:"size:100;not null;uniqueIndex"                  json:"razorpay_order_id"`
	RazorpayPaymentID *string   `gorm:"size:100"                                       json:"razorpay_payment_id,omitempty"`
	AmountPaise     int64       `gorm:"not null"                                       json:"amount_paise"`
	Currency        string      `gorm:"size:10;not null;default:'INR'"                 json:"currency"`
	Credits         int64       `gorm:"not null"                                       json:"credits"`
	Status          OrderStatus `gorm:"size:20;not null;default:'created'"             json:"status"`
	CreatedAt       time.Time   `json:"created_at"`
	UpdatedAt       time.Time   `json:"updated_at"`
}

func (Order) TableName() string { return "payment_orders" }

// ─── Request / Response DTOs ───────────────────────────────────────────────────

type CreateOrderRequest struct {
	PlanID string `json:"plan_id" binding:"required"`
}

type CreateOrderResponse struct {
	OrderID  string `json:"order_id"`
	Amount   int64  `json:"amount"` // paise
	Currency string `json:"currency"`
	KeyID    string `json:"key_id"`
	PlanID   string `json:"plan_id"`
	Credits  int64  `json:"credits"`
}

type VerifyRequest struct {
	RazorpayOrderID   string `json:"razorpay_order_id" binding:"required"`
	RazorpayPaymentID string `json:"razorpay_payment_id" binding:"required"`
	RazorpaySignature string `json:"razorpay_signature" binding:"required"`
}

type VerifyResponse struct {
	CreditsAdded int64 `json:"credits_added"`
	CreditsTotal int64 `json:"credits_total"`
}
