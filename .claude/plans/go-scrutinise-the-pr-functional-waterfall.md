# Fix: FindAndUpdateExpiredContracts loop

## Change
File: `services/handset/internal/storage/storage.go`

Add a `ctx.Err()` check and a 100-iteration cap to the `FindAndUpdateExpiredContracts` loop.

```go
const maxExpiredContractsBatch = 100

func (s storage) FindAndUpdateExpiredContracts(ctx context.Context) ([]models.Contract, error) {
    now := s.nowFunc()
    filter := bson.M{
        "status":    models.ContractStatusHandsetOrdered,
        "expiresAt": bson.M{"$lte": now},
    }
    update := bson.M{
        "$set": bson.M{
            "status":    models.ContractStatusExpired,
            "updatedAt": now,
        },
    }
    opts := options.FindOneAndUpdate().SetReturnDocument(options.After)

    var expired []models.Contract
    for range maxExpiredContractsBatch {
        if err := ctx.Err(); err != nil {
            return expired, err
        }
        var contract models.Contract
        err := s.contractsCollection.FindOneAndUpdate(ctx, filter, update, opts).Decode(&contract)
        if errors.Is(err, mongo.ErrNoDocuments) {
            break
        }
        if err != nil {
            return expired, fmt.Errorf("could not expire contract: %w", err)
        }
        expired = append(expired, contract)
    }

    return expired, nil
}
```

## Verification
- Existing storage tests cover the loop (no-docs, multi-doc, mid-error). Add a test for the ctx-cancelled case if desired.
- `go test ./services/handset/...`
