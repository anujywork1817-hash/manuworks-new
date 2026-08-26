package qdrant

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	qdrant "github.com/qdrant/go-client/qdrant"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	"github.com/yourusername/docassist/config"
	"github.com/yourusername/docassist/pkg/logger"
)

// ─── Types ────────────────────────────────────────────────────────────────────

// Point represents a single vector + metadata stored in Qdrant.
type Point struct {
	ID         string    // Qdrant point ID (UUID string)
	Vector     []float32 // Embedding vector
	DocumentID string    // Source document UUID
	ChunkID    string    // Source chunk UUID
	ChunkIndex int       // Position within document
	PageNumber int       // Page number in source doc
	Content    string    // The actual text chunk (for retrieval)
	UserID     string    // Owner — used for access-scoped search
}

// SearchResult is returned from semantic search queries.
type SearchResult struct {
	ChunkID    string  `json:"chunk_id"`
	DocumentID string  `json:"document_id"`
	Content    string  `json:"content"`
	Score      float32 `json:"score"` // Cosine similarity 0–1
	PageNumber int     `json:"page_number"`
	ChunkIndex int     `json:"chunk_index"`
}

// ─── Client ───────────────────────────────────────────────────────────────────

type Client struct {
	conn          *grpc.ClientConn
	pointsClient  qdrant.PointsClient
	collectClient qdrant.CollectionsClient
	cfg           *config.QdrantConfig
}

func NewClient(cfg *config.QdrantConfig) (*Client, error) {
	addr := fmt.Sprintf("%s:%d", cfg.Host, cfg.GRPCPort)

	conn, err := grpc.Dial(addr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
		grpc.WithTimeout(10*1e9), // 10 second connection timeout
	)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Qdrant at %s: %w", addr, err)
	}

	client := &Client{
		conn:          conn,
		pointsClient:  qdrant.NewPointsClient(conn),
		collectClient: qdrant.NewCollectionsClient(conn),
		cfg:           cfg,
	}

	return client, nil
}

func (c *Client) Close() {
	if c.conn != nil {
		_ = c.conn.Close()
	}
}

// ─── Collection Management ────────────────────────────────────────────────────

// EnsureCollection creates the collection if it doesn't exist.
// Called once at startup in main.go.
func (c *Client) EnsureCollection(ctx context.Context) error {
	// Check if collection already exists
	resp, err := c.collectClient.List(ctx, &qdrant.ListCollectionsRequest{})
	if err != nil {
		return fmt.Errorf("list collections: %w", err)
	}

	for _, col := range resp.Collections {
		if col.Name == c.cfg.CollectionName {
			logger.Info("Qdrant collection already exists",
				logger.Str("collection", c.cfg.CollectionName),
			)
			return nil
		}
	}

	// Create new collection with cosine distance (best for text embeddings)
	vectorSize := uint64(c.cfg.VectorSize)
	_, err = c.collectClient.Create(ctx, &qdrant.CreateCollection{
		CollectionName: c.cfg.CollectionName,
		VectorsConfig: &qdrant.VectorsConfig{
			Config: &qdrant.VectorsConfig_Params{
				Params: &qdrant.VectorParams{
					Size:     vectorSize,
					Distance: qdrant.Distance_Cosine,
					// HNSW index for fast approximate nearest-neighbour search
					HnswConfig: &qdrant.HnswConfigDiff{
						M:           ptr64(16),  // Connections per layer — higher = more accurate, more RAM
						EfConstruct: ptr64(100), // Build-time accuracy
					},
				},
			},
		},
		// Optimiser: balance between indexing speed and search speed
		OptimizersConfig: &qdrant.OptimizersConfigDiff{
			DefaultSegmentNumber: ptr64(2),
		},
		// Enable payload indexing for filtered search
		OnDiskPayload: boolPtr(false),
	})

	if err != nil {
		return fmt.Errorf("create collection: %w", err)
	}

	// Create payload indexes for filtered search
	// This lets us filter by document_id or user_id before vector search
	if err := c.createPayloadIndex(ctx, "document_id"); err != nil {
		logger.Warn("Failed to create document_id index", logger.Str("error", err.Error()))
	}
	if err := c.createPayloadIndex(ctx, "user_id"); err != nil {
		logger.Warn("Failed to create user_id index", logger.Str("error", err.Error()))
	}

	logger.Info("Qdrant collection created",
		logger.Str("collection", c.cfg.CollectionName),
		logger.Int("vector_size", c.cfg.VectorSize),
	)

	return nil
}

func (c *Client) createPayloadIndex(ctx context.Context, fieldName string) error {
	_, err := c.pointsClient.CreateFieldIndex(ctx, &qdrant.CreateFieldIndexCollection{
		CollectionName: c.cfg.CollectionName,
		FieldName:      fieldName,
		FieldType:      qdrant.FieldType_FieldTypeKeyword.Enum(),
	})
	return err
}

// ─── Upsert Points ────────────────────────────────────────────────────────────

// UpsertPoint stores a single vector point. Uses upsert so re-processing
// a document safely overwrites existing vectors.
func (c *Client) UpsertPoint(ctx context.Context, point Point) error {
	return c.UpsertPoints(ctx, []Point{point})
}

// UpsertPoints stores multiple vectors in a single batch request.
// More efficient than individual upserts for large documents.
func (c *Client) UpsertPoints(ctx context.Context, points []Point) error {
	if len(points) == 0 {
		return nil
	}

	qdrantPoints := make([]*qdrant.PointStruct, 0, len(points))

	for _, p := range points {
		// Parse UUID — Qdrant uses its own UUID type
		uid, err := uuid.Parse(p.ID)
		if err != nil {
			// Generate new ID if invalid
			uid = uuid.New()
		}

		qdrantPoints = append(qdrantPoints, &qdrant.PointStruct{
			Id: &qdrant.PointId{
				PointIdOptions: &qdrant.PointId_Uuid{
					Uuid: uid.String(),
				},
			},
			Vectors: &qdrant.Vectors{
				VectorsOptions: &qdrant.Vectors_Vector{
					Vector: &qdrant.Vector{
						Data: p.Vector,
					},
				},
			},
			// Payload stores metadata for filtering and retrieval
			Payload: map[string]*qdrant.Value{
				"document_id": strVal(p.DocumentID),
				"chunk_id":    strVal(p.ChunkID),
				"user_id":     strVal(p.UserID),
				"content":     strVal(p.Content),
				"chunk_index": intVal(int64(p.ChunkIndex)),
				"page_number": intVal(int64(p.PageNumber)),
			},
		})
	}

	waitUpsert := true
	_, err := c.pointsClient.Upsert(ctx, &qdrant.UpsertPoints{
		CollectionName: c.cfg.CollectionName,
		Wait:           &waitUpsert,
		Points:         qdrantPoints,
	})
	if err != nil {
		return fmt.Errorf("qdrant upsert: %w", err)
	}

	logger.Info("Vectors upserted to Qdrant",
		logger.Int("count", len(points)),
		logger.Str("collection", c.cfg.CollectionName),
	)

	return nil
}

// ─── Search ───────────────────────────────────────────────────────────────────

// Search performs semantic search across all documents.
// Returns the top-k most similar chunks by cosine similarity.
func (c *Client) Search(ctx context.Context, queryVector []float32, limit int) ([]SearchResult, error) {
	return c.searchWithFilter(ctx, queryVector, nil, limit)
}

// SearchByDocument restricts semantic search to a single document.
// Used for "chat with document" — only searches within that document's chunks.
func (c *Client) SearchByDocument(ctx context.Context, queryVector []float32, documentID string, limit int) ([]SearchResult, error) {
	filter := &qdrant.Filter{
		Must: []*qdrant.Condition{
			{
				ConditionOneOf: &qdrant.Condition_Field{
					Field: &qdrant.FieldCondition{
						Key: "document_id",
						Match: &qdrant.Match{
							MatchValue: &qdrant.Match_Keyword{
								Keyword: documentID,
							},
						},
					},
				},
			},
		},
	}
	return c.searchWithFilter(ctx, queryVector, filter, limit)
}

// SearchByUser restricts semantic search to documents owned by a specific user.
// Prevents users from searching each other's documents.
func (c *Client) SearchByUser(ctx context.Context, queryVector []float32, userID string, limit int) ([]SearchResult, error) {
	filter := &qdrant.Filter{
		Must: []*qdrant.Condition{
			{
				ConditionOneOf: &qdrant.Condition_Field{
					Field: &qdrant.FieldCondition{
						Key: "user_id",
						Match: &qdrant.Match{
							MatchValue: &qdrant.Match_Keyword{
								Keyword: userID,
							},
						},
					},
				},
			},
		},
	}
	return c.searchWithFilter(ctx, queryVector, filter, limit)
}

func (c *Client) searchWithFilter(ctx context.Context, queryVector []float32, filter *qdrant.Filter, limit int) ([]SearchResult, error) {
	if limit <= 0 {
		limit = 5
	}

	limitU := uint64(limit)
	withPayload := &qdrant.WithPayloadSelector{
		SelectorOptions: &qdrant.WithPayloadSelector_Enable{Enable: true},
	}

	resp, err := c.pointsClient.Search(ctx, &qdrant.SearchPoints{
		CollectionName: c.cfg.CollectionName,
		Vector:         queryVector,
		Filter:         filter,
		Limit:          limitU,
		WithPayload:    withPayload,
		// Minimum similarity threshold — ignore low-quality matches
		ScoreThreshold: float32Ptr(0.5),
		Params: &qdrant.SearchParams{
			// ef controls search accuracy vs speed trade-off
			// Higher ef = more accurate but slower
			HnswEf: ptr64(128),
			Exact:  boolPtr(false), // Approximate is fine for semantic search
		},
	})
	if err != nil {
		return nil, fmt.Errorf("qdrant search: %w", err)
	}

	results := make([]SearchResult, 0, len(resp.Result))
	for _, hit := range resp.Result {
		result := SearchResult{
			Score: hit.Score,
		}

		if payload := hit.Payload; payload != nil {
			result.ChunkID = getStrPayload(payload, "chunk_id")
			result.DocumentID = getStrPayload(payload, "document_id")
			result.Content = getStrPayload(payload, "content")
			result.PageNumber = int(getIntPayload(payload, "page_number"))
			result.ChunkIndex = int(getIntPayload(payload, "chunk_index"))
		}

		results = append(results, result)
	}

	return results, nil
}

// ─── Delete ───────────────────────────────────────────────────────────────────

// DeleteByDocument removes all vectors for a document.
// Called when a document is deleted from the system.
func (c *Client) DeleteByDocument(ctx context.Context, documentID string) error {
	waitDelete := true
	_, err := c.pointsClient.Delete(ctx, &qdrant.DeletePoints{
		CollectionName: c.cfg.CollectionName,
		Wait:           &waitDelete,
		Points: &qdrant.PointsSelector{
			PointsSelectorOneOf: &qdrant.PointsSelector_Filter{
				Filter: &qdrant.Filter{
					Must: []*qdrant.Condition{
						{
							ConditionOneOf: &qdrant.Condition_Field{
								Field: &qdrant.FieldCondition{
									Key: "document_id",
									Match: &qdrant.Match{
										MatchValue: &qdrant.Match_Keyword{
											Keyword: documentID,
										},
									},
								},
							},
						},
					},
				},
			},
		},
	})
	if err != nil {
		return fmt.Errorf("qdrant delete by document: %w", err)
	}

	logger.Info("Vectors deleted from Qdrant",
		logger.Str("document_id", documentID),
	)
	return nil
}

// ─── Health Check ─────────────────────────────────────────────────────────────

func (c *Client) HealthCheck(ctx context.Context) error {
	_, err := c.collectClient.List(ctx, &qdrant.ListCollectionsRequest{})
	return err
}

// CollectionInfo returns stats about the collection (point count, etc.)
func (c *Client) CollectionInfo(ctx context.Context) (*qdrant.GetCollectionInfoResponse, error) {
	return c.collectClient.Get(ctx, &qdrant.GetCollectionInfoRequest{
		CollectionName: c.cfg.CollectionName,
	})
}

// ─── Payload helpers ──────────────────────────────────────────────────────────

func strVal(s string) *qdrant.Value {
	return &qdrant.Value{
		Kind: &qdrant.Value_StringValue{StringValue: s},
	}
}

func intVal(i int64) *qdrant.Value {
	return &qdrant.Value{
		Kind: &qdrant.Value_IntegerValue{IntegerValue: i},
	}
}

func getStrPayload(payload map[string]*qdrant.Value, key string) string {
	v, ok := payload[key]
	if !ok {
		return ""
	}
	if sv, ok := v.Kind.(*qdrant.Value_StringValue); ok {
		return sv.StringValue
	}
	return ""
}

func getIntPayload(payload map[string]*qdrant.Value, key string) int64 {
	v, ok := payload[key]
	if !ok {
		return 0
	}
	if iv, ok := v.Kind.(*qdrant.Value_IntegerValue); ok {
		return iv.IntegerValue
	}
	return 0
}

// ─── Pointer helpers ──────────────────────────────────────────────────────────

func ptr32(v uint32) *uint32        { return &v }
func ptr64(v uint64) *uint64        { return &v }
func boolPtr(v bool) *bool          { return &v }
func float32Ptr(v float32) *float32 { return &v }

