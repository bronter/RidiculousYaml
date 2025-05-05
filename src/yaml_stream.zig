const std = @import("std");

const Options = @import("options.zig");
const bom = @import("bom.zig");
const YamlReader = @import("yaml_reader.zig");
const Document = @import("document.zig");
const builtin = @import("builtin");

const Self = @This();

reader: YamlReader,
allocator: std.mem.Allocator,
prev_encoding: ?bom.EncodingInfo,
supported_encodings: Options.EncodingOptions,

pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, comptime options: Options) Self {
    return Self {
        .reader = YamlReader.init(allocator, reader, options),
        .allocator = allocator,
        .prev_encoding = null,
        .supported_encodings = options.encodings,
    };
}

fn _nextDocument(self: *Self, comptime E: bom.EncodingInfo) !?Document {
    _ = self;
    return error.TODO;
}

pub fn nextDocument(self: *Self) !?Document {
    var encoding: bom.Encoding = undefined;
    var endian: std.builtin.Endian = undefined;
    if (self.prev_encoding) |prev_encoding| {
        encoding, endian = prev_encoding;
    } else {
        const new_encoding = try self.reader.readBOM();
        self.prev_encoding = new_encoding;
        encoding, endian = new_encoding;
    }

    const se = self.supported_encodings;

    // Dunno if it's a good idea to try to force the compiler to generate five different parsers,
    // but let's try it and see.
    return switch (encoding) {
        .utf8 => if (se.utf8) self._nextDocument(.{ .utf8, builtin.cpu.arch.endian() }) else error.UnsupportedUTF8Document,
        .utf16 => switch (endian) {
            .little => if (se.utf16le) self._nextDocument(.{ .utf16, .little }) else error.UnsupportedUTF16LeDocument,
            .big => if (se.utf16be) self._nextDocument(.{ .utf16, .big}) else error.UnsupportedUTF16BeDocument,
        },
        .utf32 => switch (endian) {
            .little => if (se.utf32le) self._nextDocument(.{ .utf32, .little }) else error.UnsupportedUTF32LeDocument,
            .big => if (se.utf32be) self._nextDocument(.{ .utf32, .big }) else error.UnsupportedUTF32BeDocument,
        },
    };
}