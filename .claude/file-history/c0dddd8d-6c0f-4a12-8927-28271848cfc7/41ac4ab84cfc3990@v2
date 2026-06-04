# Context

`expires_at` was being calculated in `consumer.go` after `UpdateContractStatusByID` succeeded. If `UpdateContractExpiresAt` then failed, the message was nacked but on retry the `HANDSET_ORDERED` early-exit guard fired — meaning `expires_at` was permanently never written and the contract would never be expired by the job.

Fix: move `expires_at` calculation into the storage layer, computed atomically alongside `signed_at` in the same `$set` operation in `UpdateContractEligibilityApproved`. This way `expires_at` is always present on any contract that has a `signed_at`.

## Approach

### 1. `models/models.go` — add `ContractMonths` to `EligibilityOutcome`

```go
type EligibilityOutcome struct {
    Decision           string
    AgreementID        string
    DocusignEnvelopeID string
    ContractMonths     string   // add this
    SignedAt           *time.Time
    CompletedAt        *time.Time
}
```

### 2. `service/service.go` — populate `ContractMonths` when building the outcome

At the `EligibilityCallbackSuccess` call site (line ~297), the `contract` is already fetched. Add `ContractMonths: contract.ContractMonths` to the `EligibilityOutcome` struct literal passed to `UpdateContractEligibilityApproved`.

### 3. `storage/storage.go` — compute `expiresAt` atomically in `UpdateContractEligibilityApproved`

Inside the `if outcome.SignedAt != nil` block, also compute and set `expiresAt` when `ContractMonths` parses successfully:

```go
if outcome.SignedAt != nil {
    setFields["signedAt"] = outcome.SignedAt
    if outcome.ContractMonths != "" {
        if months, err := strconv.Atoi(outcome.ContractMonths); err == nil {
            setFields["expiresAt"] = outcome.SignedAt.AddDate(0, months, 0)
        }
    }
}
```

Delete `UpdateContractExpiresAt` entirely from `storage.go`.

### 4. `consumer/consumer.go` — remove `expires_at` logic and interface method

- Remove `UpdateContractExpiresAt` from the `Storage` interface.
- Remove the entire `if contract.SignedAt != nil { ... UpdateContractExpiresAt ... }` block from `ConsumeMobileHandsetOrdered`.

### 5. `consumer/mocks/consumer.go` — remove `UpdateContractExpiresAt` mock

Delete the `UpdateContractExpiresAt` and `UpdateContractExpiresAt` recorder methods.

## Files touched

- `services/handset/internal/models/models.go`
- `services/handset/internal/service/service.go`
- `services/handset/internal/storage/storage.go`
- `services/handset/internal/consumer/consumer.go`
- `services/handset/internal/consumer/mocks/consumer.go`

## Tests to update

- `storage/storage_test.go` — add a case to the `UpdateContractEligibilityApproved` describe block asserting that `expiresAt` is included in the `$set` when `signedAt` + `ContractMonths` are provided; add a case where `SignedAt` is nil and assert `expiresAt` is not set.
- `consumer/consumer_test.go` — remove all `store.EXPECT().UpdateContractExpiresAt(...)` expectations; remove any tests that only existed to cover that path (the expiry-at-update tests are now covered in the storage layer tests).

## Verification

```
cd services/handset && go test ./...
```
