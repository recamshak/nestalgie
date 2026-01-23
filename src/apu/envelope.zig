pub const EnvelopeType = enum {
    constant,
    decay,
};

pub const DecayEnvelope = struct {
    counter: u4 = 0,
    period: u4 = 0,
    repeat: bool = false,
    volume: u4 = 15,
};

pub const Envelope = union(EnvelopeType) {
    constant: u4,
    decay: DecayEnvelope,

    pub fn tick(self: *Envelope) void {
        switch (self.*) {
            .constant => {},
            .decay => {
                self.decay.counter -|= 1;
                if (self.decay.counter == 0) {
                    self.decay.counter = self.decay.period + 1;
                    if (self.decay.volume == 0 and self.decay.repeat) {
                        self.decay.volume = 15;
                    } else {
                        self.decay.volume -|= 1;
                    }
                }
            },
        }
    }

    pub fn reset(self: *Envelope) void {
        switch (self.*) {
            .constant => {},
            .decay => {
                self.decay.volume = 15;
                self.decay.counter = self.decay.period;
            },
        }
    }

    pub fn volume(self: *Envelope) u4 {
        return switch (self.*) {
            .constant => self.constant,
            .decay => self.decay.volume,
        };
    }
};
