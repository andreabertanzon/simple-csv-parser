const std = @import("std");
const testing = std.testing;

const Employee = struct {
    name: []const u8,
    surname: []const u8,
    address: []const u8,
    phone: []const u8,
};

pub const TokenKvp = struct {
    key: []u8,
    value: []u8,

    pub fn init(allocator: std.mem.Allocator, key: []const u8, value: []const u8) !TokenKvp {
        var self = TokenKvp{
            .key = try allocator.dupe(u8, key),
            .value = try allocator.dupe(u8, value),
        };
        return self;
    }

    pub fn deinit(self: *TokenKvp, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

pub const Entity = struct {
    kvps: std.ArrayListUnmanaged(TokenKvp),
    line: usize,

    pub fn init(allocator: std.mem.Allocator, line: usize) !Entity {
        //var kvpList = std.ArrayList(TokenKvp).init(allocator);
        var kvpList = try std.ArrayListUnmanaged(TokenKvp).initCapacity(allocator, 4);

        var self = Entity{
            .kvps = kvpList,
            .line = line,
        };

        return self;
    }

    pub fn addKvp(self: *Entity, key: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
        var kvp = try TokenKvp.init(allocator, key, value);
        try self.kvps.append(allocator, kvp);
    }

    pub fn deinit(self: *Entity, allocator: std.mem.Allocator) void {
        for (self.kvps.items) |*kvp| {
            kvp.deinit(allocator);
        }
        self.kvps.deinit(allocator);
    }

    pub fn print(self: *Entity) void {
        std.debug.print("Entity: {d}\n", .{self.line});
        for (self.kvps.items) |kvp| {
            std.debug.print("KVP: {s} - {s}\n", .{ kvp.key, kvp.value });
        }
    }
};

pub const Entities = struct {
    allocator: std.mem.Allocator,
    entities: std.ArrayListUnmanaged(Entity),

    pub fn init(allocator: std.mem.Allocator) !Entities {
        var entities = try std.ArrayListUnmanaged(Entity).initCapacity(allocator, 4);

        var self = Entities{
            .allocator = allocator,
            .entities = entities,
        };

        return self;
    }

    pub fn addEntity(self: *Entities, entity: Entity) !void {
        try self.entities.append(self.allocator, entity);
    }

    pub fn deinit(self: *Entities) void {
        for (self.entities.items) |*entity| {
            entity.deinit(self.allocator);
        }
        self.entities.deinit(self.allocator);
    }
};

test "kvp testing" {
    std.debug.print("KVP testing\n", .{});
    var testingAllocator = std.testing.allocator;
    var value: []const u8 = "value";
    var key: []const u8 = "key";
    var entity = try Entity.init(testingAllocator, 0);
    try entity.addKvp(key, value, testingAllocator);

    var entities = try Entities.init(testingAllocator);
    defer entities.deinit();
    try entities.addEntity(entity);
    for (entity.kvps.items) |kvp| {
        std.debug.print("KVP: {s} - {s}\n", .{ kvp.key, kvp.value });
    }
}

/// Errors associated with readByLineTokenizedTyped
pub const Errors = error{
    InvalidHeader,
};

/// pass a T struct with the same fields as the csv file header row
/// the fields must be in the same order as the csv file header row
/// the fields must be of type []const u8 so that they can be loaded in the T struct
/// returns an ArrayList of T. The ArrayList must be deinitialized after use so are all the
/// fields of the T struct
pub fn readCsvAlloc(comptime T: type, path: []const u8, allocator: std.mem.Allocator) !Entities {
    var val: T = undefined; // needed for the inline for loop
    var entities = try Entities.init(allocator);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var size = (try file.stat()).size;
    var buff = try allocator.alloc(u8, size);
    defer allocator.free(buff);

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var i: usize = 0;
    comptime var fields = std.meta.fields(T);

    var field_names: [fields.len][]const u8 = undefined;
    var field_names_index: usize = 0;
    inline for (fields) |field| {
        field_names[field_names_index] = field.name;
        field_names_index += 1;
    }

    var field_count: usize = 0; // total header fields
    while (try in_stream.readUntilDelimiterOrEof(buff, '\n')) |line| {
        val = undefined;
        var it = std.mem.tokenize(u8, line, ",\n");

        // the first line contains the csv headers
        // we check that each header matches the struct field name
        if (i == 0) {
            while (it.next()) |token| {
                if (!std.mem.eql(u8, field_names[field_count], token)) {
                    std.debug.print("--> Invalid header: {s} != {s}\n", .{ field_names[field_count], token });
                    return error.InvalidHeader;
                }
                field_count += 1;
            }
            if (field_count != fields.len) {
                return error.InvalidHeader;
            }
            i += 1;
            continue;
        }
        field_count = 0;
        var entity = try Entity.init(allocator, i);
        while (it.next()) |token| {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field_names[field_count], field.name)) {
                    // assign field value
                    try entity.addKvp(field.name, token, allocator);
                }
            }
            field_count += 1;
        }

        try entities.addEntity(entity);
        i += 1;
    }

    return entities;
}

test "read by line" {
    var testingAllocator = std.testing.allocator;

    var result: Entities = try readCsvAlloc(
        struct {
            name: []const u8,
            surname: []const u8,
            address: []const u8,
            phone: []const u8,
        },
        "test2.csv",
        testingAllocator,
    );
    defer result.deinit();
    for (result.entities.items) |*item| {
        item.print();
    }
    try std.testing.expectEqual(result.entities.items.len, 3);
}
