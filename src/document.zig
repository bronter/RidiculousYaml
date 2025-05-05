const std = @import("std");

const bom = @import("bom.zig");
const Node = @import("node.zig");
const directive = @import("directive.zig");

const Self = @This();

arena: std.heap.ArenaAllocator,
directives: []const directive.Directive,
root_node: Node,

// TODO: Handle BOM at beginning of document; I think it has to do with utf-16 and utf-32.
//       We could wrap the reader with something like "Utf16To8Reader.init(byte_order, reader)".
//       Basically, convert to utf-8 before it hits the YamlReader so that we only have to worry about utf-8.
//       Any BOMs occurring in the stream afterwards could be automatically escaped by the wrapper;
//       if they appeared outside of quoted scalars they're technically malformed YAML anyways,
//       so in the worst case we might fail to detect one very specific edge case of malformed yaml.
//       Also, although all documents in a stream must have the same character encoding, each document can have a BOM.
pub fn parse(comptime E: bom.EncodingInfo, allocator: std.mem.Allocator, source_text: []bom.charType(E)) !Self {
    var arena = std.heap.ArenaAllocator.init(allocator); 

    return Self {
        .arena = arena,
        .root_node = try Node.parse(arena.allocator(), &yaml_reader),
    };
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}