package retry

func Connect(opts Options) bool {
	for i := 0; i < 3; i++ {
		if tryConnect(opts) {
			return true
		}
	}
	return false
}
