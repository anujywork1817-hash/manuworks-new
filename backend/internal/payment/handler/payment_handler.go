package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/yourusername/docassist/internal/payment/model"
	"github.com/yourusername/docassist/internal/payment/service"
	"github.com/yourusername/docassist/pkg/logger"
	"github.com/yourusername/docassist/pkg/middleware"
)

type PaymentHandler struct {
	svc service.PaymentService
}

func NewPaymentHandler(svc service.PaymentService) *PaymentHandler {
	return &PaymentHandler{svc: svc}
}

// CreateOrder godoc
// @Summary      Create a Razorpay order for a recharge plan
// @Tags         payments
// @Security     BearerAuth
// @Accept       json
// @Produce      json
// @Param        body body model.CreateOrderRequest true "Plan to purchase"
// @Success      200  {object} Response{data=model.CreateOrderResponse}
// @Failure      400  {object} ErrorResponse
// @Failure      401  {object} ErrorResponse
// @Router       /payments/razorpay/create-order [post]
func (h *PaymentHandler) CreateOrder(c *gin.Context) {
	userID, err := getUserID(c)
	if err != nil {
		respondError(c, http.StatusUnauthorized, "UNAUTHORIZED", "invalid user context")
		return
	}

	var req model.CreateOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	resp, err := h.svc.CreateOrder(c.Request.Context(), userID, req.PlanID)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrUnknownPlan):
			respondError(c, http.StatusBadRequest, "UNKNOWN_PLAN", err.Error())
		default:
			respondInternalError(c, err)
		}
		return
	}

	respond(c, http.StatusOK, "Order created", resp)
}

// Verify godoc
// @Summary      Verify a completed Razorpay payment and credit the account
// @Tags         payments
// @Security     BearerAuth
// @Accept       json
// @Produce      json
// @Param        body body model.VerifyRequest true "Razorpay checkout result"
// @Success      200  {object} Response{data=model.VerifyResponse}
// @Failure      400  {object} ErrorResponse
// @Failure      401  {object} ErrorResponse
// @Router       /payments/razorpay/verify [post]
func (h *PaymentHandler) Verify(c *gin.Context) {
	userID, err := getUserID(c)
	if err != nil {
		respondError(c, http.StatusUnauthorized, "UNAUTHORIZED", "invalid user context")
		return
	}

	var req model.VerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	resp, err := h.svc.VerifyPayment(c.Request.Context(), userID, &req)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrInvalidSignature):
			respondError(c, http.StatusBadRequest, "INVALID_SIGNATURE", err.Error())
		case errors.Is(err, service.ErrOrderMismatch):
			respondError(c, http.StatusForbidden, "ORDER_MISMATCH", err.Error())
		case errors.Is(err, service.ErrOrderAlreadyPaid):
			respondError(c, http.StatusConflict, "ALREADY_PROCESSED", err.Error())
		default:
			respondInternalError(c, err)
		}
		return
	}

	respond(c, http.StatusOK, "Payment verified", resp)
}

// ─── Response helpers (mirrors internal/auth/handler's envelope) ──────────────

type Response struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

type ErrorResponse struct {
	Success bool   `json:"success"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

func respond(c *gin.Context, status int, message string, data interface{}) {
	c.JSON(status, Response{Success: true, Message: message, Data: data})
}

func respondError(c *gin.Context, status int, code, message string) {
	c.JSON(status, ErrorResponse{Success: false, Code: code, Message: message})
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

func getUserID(c *gin.Context) (uuid.UUID, error) {
	raw := middleware.GetUserID(c)
	if raw == "" {
		return uuid.Nil, errors.New("user_id not in context")
	}
	return uuid.Parse(raw)
}
