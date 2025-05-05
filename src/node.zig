const std = @import("std");

const YamlReader = @import("yaml_reader.zig");

const Self = @This();

pub fn parse(allocator: std.mem.Allocator, reader: *YamlReader) !Self {
    _ = allocator;
    _ = reader;

    // TODO: Parse node
    return Self {};
}