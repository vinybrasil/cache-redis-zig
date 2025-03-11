pub const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    age: u8,
    timestamp: i64 = undefined,
};

pub const healthCheckStruct = struct {
    ping: []const u8,
};

pub const responseStruct = struct {
    id: []const u8,
    value: ?*[]const u8,
};
