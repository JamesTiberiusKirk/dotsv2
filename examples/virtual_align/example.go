// Demo file for custom.virtual_align and the gopls hints. Open it and toggle with :VirtualAlignToggle.
package example

import (
	"errors"
	"fmt"
	"time"
)

// --- go_tags: tag pairs line up with · fill ---

type Handset struct {
	ID      string    `json:"id" bson:"id"`
	BillID  int       `json:"billID" bson:"billID"`
	Active  bool      `json:"active" bson:"active"`
	Created time.Time `json:"createdAt,omitempty" bson:"createdAt"`

	// blank line or own-line comment above starts a new alignment block
	StockBase    int    `bson:"stockBase"`
	PrimaryImage string `json:"primaryImage,omitempty" bson:"-"`
	Versions     []int  `json:"versions" bson:"versions"` // trailing comment keeps the block
}

// --- gopls hints: field names on keyless literals, constant values ---

type Point struct {
	X, Y int
}

const Timeout = 30 * time.Second

var origin = Point{1, 2}

var wait = Timeout

// --- go_assign: consecutive assignments line up their = ---

func Copy(dst, src *Handset) {
	dst.ID = src.ID
	dst.PrimaryImage = src.PrimaryImage
	n := len(src.Versions)
	dst.Versions = make([]int, n)

	// blank line or comment above starts a new group
	dst.Active = src.Active
	dst.StockBase += src.StockBase
}

// --- go_fold: if with a single return ---

func Load(id string) (*Handset, error) {
	h, err := find(id)
	if err != nil {
		return nil, err
	}
	if h == nil {
		return nil, errors.New("not found")
	}
	return h, nil
}

// --- go_fold: if with a single panic ---

func MustLoad(id string) *Handset {
	h, err := Load(id)
	if err != nil {
		panic(err)
	}
	return h
}

// --- go_fold: functions with a single return ---

func find(id string) (*Handset, error) {
	return &Handset{ID: id}, nil
}

func (h *Handset) Label() string {
	return fmt.Sprintf("%s-%d", h.ID, h.BillID)
}

var double = func(n int) int {
	return n * 2
}

// --- go_fold: case clauses with one statement ---

func Kind(v any) string {
	switch v.(type) {
	case int:
		return "int"
	case string:
		return "string"
	default:
		return "other"
	}
}

// --- NOT folded: more than one statement, comment inside, or an else ---

func Skipped(err error) error {
	if err != nil {
		fmt.Println(err)
		return err
	}
	if err != nil {
		// comment blocks the fold
		return err
	}
	if err == nil {
		return nil
	} else {
		return err
	}
}
