const std = @import("std");

const Options = @import("options.zig");
const bom = @import("bom.zig");

const Self = @This();

reader: std.io.AnyReader,
allocator: std.mem.Allocator,

// This is just a raw buffer, it could be interpreted as a []u8, []u16, or []u32,
// depending on the encoding that is passed into certain functions
buffer: std.ArrayList(u8),
read_length: usize,

pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, comptime options: Options) Self {
    return Self {
        .reader = reader,
        .allocator = allocator,
        .buffer = std.ArrayList(u8).initCapacity(
            allocator,
            options.initial_read_capacity
        ),
        .read_len = options.read_length,
    };
}

// Maybe this should just be part of the document read function
// As in, read the bom, then read to an end marker, then return the bom and store the document buffer.
pub fn readBOM(self: *Self) !bom.EncodingInfo {
    var bom_bytes = [4]u8 {0, 0, 0, 0};
    const bytes_read = try self.reader.read(&bom_bytes);

    const bom_info = bom.determineEncodingAndByteOrder(bom_bytes);

    // Trim off any padding and skip over the BOM since we've already parsed it.
    const text_start = bom_info.bom_length;
    self.buffer.appendSlice(bom_bytes[text_start..bytes_read]);

    return bom_info.encoding_info;
}

// Read to either a directives end marker ("---") or a document end marker ("...")
// Note that a directives end marker could also mean end of document if there are no directives,
// but the YamlReader won't be able to determine if that is the case on its own.
fn readToEndMarker(self: *Self, comptime encoding_info: bom.EncodingInfo) ![]bom.charType(encoding_info) {
}

