package retry

func Connect(opts Options) bool {
	for {
		if tryConnect(opts) {
			return true
		}
	}
}
