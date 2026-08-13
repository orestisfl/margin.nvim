package retry

import (
	"context"
	"time"
)

type Retrier struct {
	MaxAttempts int
	Delay       time.Duration
}

func (r Retrier) Run(ctx context.Context, fn func() error) error {
	var err error
	for attempt := 0; attempt < r.MaxAttempts; attempt++ {
		if err = fn(); err == nil {
			return nil
		}
		time.Sleep(r.Delay)
	}
	return err
}
