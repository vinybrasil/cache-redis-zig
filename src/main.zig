const std = @import("std");
const json = std.json;
const lib = @import("zap_redis_lib");

const net = std.net;

const okredis = @import("okredis");
const Client = okredis.Client;

const Allocator = std.mem.Allocator;

const zap = @import("zap");
const OrErr = okredis.types.OrErr;

const entities = @import("entities.zig");
const DefaultContext = std.array_hash_map.DefaultContext;

fn not_found(req: zap.Request) void {
    std.debug.print("not found handler", .{});

    req.sendBody("Not found") catch return;
}

pub const CachePackage = struct {
    const Self = @This();

    allocator: Allocator,
    redisCache: RedisCache,
    users: std.HashMap(
        u32,
        entities.User,
        std.hash_map.AutoContext(u32),
        80,
    ),

    pub fn init(
        allocator: Allocator,
        redisCache: RedisCache,
        users: std.HashMap(
            u32,
            entities.User,
            std.hash_map.AutoContext(u32),
            80,
        ),
    ) Self {
        return .{
            .allocator = allocator,
            //.client = client,
            .redisCache = redisCache,
            .users = users,
        };
    }

    pub fn healthCheck(self: *Self, req: zap.Request) void {
        std.debug.print("Allocator: {any}\n", .{self.allocator});

        if (std.mem.eql(u8, req.method.?, "GET")) {
            const healthCheckObject = entities.healthCheckStruct{ .ping = "pong" };

            var buf: [500]u8 = undefined;
            var json_to_send: []const u8 = undefined;
            if (zap.stringifyBuf(&buf, healthCheckObject, .{})) |json_read| {
                json_to_send = json_read;
            } else {
                json_to_send = "null";
            }

            // send health check to the client
            req.setContentType(.JSON) catch return;
            req.sendBody(json_to_send) catch return;
        }
    }

    pub fn getValues(self: *Self, req: zap.Request) !void {
        if (std.mem.eql(u8, req.method.?, "GET")) {
            var id_request: []const u8 = undefined;

            var response: []const u8 = "";

            if (req.body) |body| {
                const maybe_user: ?std.json.Parsed(std.json.Value) = std.json.parseFromSlice(
                    std.json.Value,
                    self.allocator,
                    body,
                    .{},
                ) catch null;

                if (maybe_user) |parsed_user| {
                    defer parsed_user.deinit();

                    if (parsed_user.value.object.get("id")) |id_from_req| {
                        id_request = try self.allocator.dupe(u8, id_from_req.string);
                    }
                } else {
                    std.log.err("Failed to parse JSON", .{});
                }
            }

            switch (try self.redisCache.client.sendAlloc(
                OrErr([]u8),
                self.allocator,
                .{ "GET", id_request },
            )) {
                .Ok => |value| {
                    std.debug.print("Found value on redis: {s}\n", .{value});
                    response = try self.allocator.dupe(u8, value);
                },
                .Nil => {
                    // get from the fake db -----------------------------------------------

                    // Parse string to u32
                    const id_request_int = try std.fmt.parseInt(
                        u8,
                        id_request,
                        10,
                    );
                    const id_request_casted: u32 = @intCast(id_request_int);

                    if (self.users.getPtr(id_request_casted)) |user| {
                        user.timestamp = std.time.timestamp();
                        const json_string = try json.stringifyAlloc(
                            self.allocator,
                            user,
                            .{},
                        );
                        defer self.allocator.free(json_string);
                        // -----------------------------------------------
                        // if finds it in the db, sends to redis:
                        try self.redisCache.client.send(void, .{ "SET", id_request, json_string, "EX", self.redisCache.ttl });
                        response = try self.allocator.dupe(u8, json_string);
                    } else {
                        std.log.err("User {d} not found", .{id_request_casted});
                    }
                },

                .Err => |err| std.log.err("error code = {any}\n", .{err.getCode()}),
            }

            const responseObject = entities.responseStruct{
                .id = id_request,
                .value = &response,
            };

            defer self.allocator.free(response);
            defer self.allocator.free(id_request);

            var buf: [500]u8 = undefined;
            var json_to_send: []const u8 = undefined;
            if (zap.stringifyBuf(&buf, responseObject, .{})) |json_read| {
                json_to_send = json_read;
            } else {
                json_to_send = "null";
            }

            // send response to the client
            req.setContentType(.JSON) catch return;
            req.sendBody(json_to_send) catch return;
        }
    }
};

pub const RedisCache: type = struct {
    const Self = @This();
    ttl: []const u8,
    client: Client = undefined,
    pub fn init(self: *Self, ttl: []u8, client: Client) !void {
        self.ttl = ttl;
        self.client = client;
    }
};

pub fn main() !void {
    var client: Client = undefined;

    const addr = try net.Address.parseIp4("172.20.0.2", 6379);
    // to run outside docker
    //const addr = try net.Address.parseIp4("127.0.0.1", 6379);
    const connection = try net.tcpConnectToAddress(addr);

    try client.init(connection);
    defer client.close();

    const redischace: RedisCache = RedisCache{
        .ttl = "30",
        .client = client,
    };

    std.debug.print("TTL: {s}\n", .{redischace.ttl});

    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};

    const allocator = gpa.allocator();

    var simpleRouter = zap.Router.init(allocator, .{
        .not_found = not_found,
    });
    defer simpleRouter.deinit();

    // fake database. Using hashmap to emulate Python dicts ----------------------------------------
    var users = std.AutoHashMap(u32, entities.User).init(allocator);
    defer users.deinit();

    try users.put(1, entities.User{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });
    try users.put(2, entities.User{
        .id = 2,
        .name = "Bob",
        .email = "bob@example.com",
        .age = 30,
    });
    try users.put(3, entities.User{
        .id = 3,
        .name = "Charlie",
        .email = "charlie@example.com",
        .age = 22,
    });

    // ----------------------------------------
    var cachePackage = CachePackage.init(
        allocator,
        redischace,
        users,
    );

    try simpleRouter.handle_func("/healthcheck", &cachePackage, &CachePackage.healthCheck);
    try simpleRouter.handle_func("/getvalues", &cachePackage, &CachePackage.getValues);

    const duration = std.time.ns_per_s * 3;

    std.time.sleep(duration);

    std.debug.print("Starting Zap...\n", .{});

    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = simpleRouter.on_request_handler(),
        .log = true,
        .max_clients = 100000,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}
