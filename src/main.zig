const std = @import("std");
const testing = std.testing;

const Employee = struct {
    name: []const u8,
    surname: []const u8,
    address: []const u8,
    phone: []const u8,
};

/// Errors associated with readByLineTokenizedTyped
pub const Errors = error{
    InvalidHeader,
};

/// pass a T struct with the same fields as the csv file header row
/// the fields must be in the same order as the csv file header row
/// the fields must be of type []const u8 so that they can be loaded in the T struct
/// returns an ArrayList of T. The ArrayList must be deinitialized after use so are all the
/// fields of the T struct
pub fn readCsvAlloc(comptime T: type, path: []const u8, allocator: std.mem.Allocator) !std.ArrayList(T) {
    var val: T = undefined; // needed for the inline for loop
    var arrayList = std.ArrayList(T).init(allocator);
    var buff = try allocator.alloc(u8, 1024);
    defer allocator.free(buff);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

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
                //std.debug.print("TOKEN: {s} - STRUCT: {s}\n", .{ token, field_names[field_count] });
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
        //var it = std.mem.tokenize(u8, line, ",\n");
        field_count = 0;
        while (it.next()) |token| {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field_names[field_count], field.name)) {
                    // assign field value
                    var value: []const u8 = token;
                    @field(val, field.name) = try allocator.dupe(u8, value);
                }
            }
            field_count += 1;
        }
        try arrayList.append(val);
        i += 1;
    }

    return arrayList;
}

test "read by line" {
    var testingAllocator = std.testing.allocator;

    var result: std.ArrayList(Employee) = try readCsvAlloc(Employee, "test2.csv", testingAllocator);
    defer result.deinit();
    for (result.items) |item| {
        std.debug.print("ITEM: {s}, {s}, {s}, {s}\n", .{ item.name, item.surname, item.address, item.phone });
        testingAllocator.free(item.name);
        testingAllocator.free(item.surname);
        testingAllocator.free(item.address);
        testingAllocator.free(item.phone);
    }
    try std.testing.expectEqual(result.items.len, 3);
}
