// Package razorpay is a minimal client for the two Razorpay Orders API calls
// this app needs (create order, verify payment signature). It intentionally
// avoids pulling in a full SDK for such a small surface.
package razorpay

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const ordersURL = "https://api.razorpay.com/v1/orders"

type Client struct {
	keyID     string
	keySecret string
	http      *http.Client
}

func NewClient(keyID, keySecret string) *Client {
	return &Client{
		keyID:     keyID,
		keySecret: keySecret,
		http:      &http.Client{Timeout: 15 * time.Second},
	}
}

type createOrderRequest struct {
	Amount   int64  `json:"amount"`
	Currency string `json:"currency"`
	Receipt  string `json:"receipt"`
}

type OrderResponse struct {
	ID       string `json:"id"`
	Amount   int64  `json:"amount"`
	Currency string `json:"currency"`
	Status   string `json:"status"`
}

// CreateOrder calls Razorpay's Orders API with HTTP basic auth (key:secret),
// the standard way to authenticate server-side Razorpay requests.
func (c *Client) CreateOrder(amountPaise int64, currency, receipt string) (*OrderResponse, error) {
	body, err := json.Marshal(createOrderRequest{
		Amount:   amountPaise,
		Currency: currency,
		Receipt:  receipt,
	})
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest(http.MethodPost, ordersURL, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.SetBasicAuth(c.keyID, c.keySecret)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return nil, fmt.Errorf("razorpay order creation failed (status %d): %s", resp.StatusCode, string(respBody))
	}

	var order OrderResponse
	if err := json.Unmarshal(respBody, &order); err != nil {
		return nil, err
	}
	return &order, nil
}

// VerifySignature checks the HMAC-SHA256 signature Razorpay's checkout
// returns after a successful payment, per their documented scheme:
// signature = HMAC_SHA256(order_id + "|" + payment_id, key_secret).
func (c *Client) VerifySignature(orderID, paymentID, signature string) bool {
	mac := hmac.New(sha256.New, []byte(c.keySecret))
	mac.Write([]byte(orderID + "|" + paymentID))
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(signature))
}
