pub const EnvelopeType = enum {
    constant,
    decay,
};

pub const DecayEnvelope = struct {
    timer_counter: u4 = 0,
    timer_reset_counter: u4 = 0,
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
                self.decay.timer_counter -|= 1;
                if (self.decay.timer_counter == 0) {
                    self.decay.timer_counter = self.decay.timer_reset_counter + 1;
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
                self.decay.timer_counter = self.decay.timer_reset_counter;
            },
        }
    }
};
