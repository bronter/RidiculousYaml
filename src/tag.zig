const std = @import("std");

const util = @import("util.zig");

pub const TagHandle = union(enum) {
    named: []const u8,
    primary,
    secondary,

    pub fn parse(string: []const u8) !TagHandle {
        if (string.len == 0) return error.EmptyTagHandle;

        if (string[0] == '!' and string[string.len - 1] == '!') {
            if (string.len == 1) {
                return TagHandle.primary;
            } else if (string.len == 2) {
                return TagHandle.secondary;
            } else {
                const maybe_tag_name = string[1..(string.len - 1)];
                if (util.isWordCharString(maybe_tag_name)) {
                    return TagHandle {
                        .named = maybe_tag_name,
                    };
                } else {
                    return error.InvalidNamedTagHandle;
                }
            }
        } else {
            return error.InvalidTagHandle;
        }
    }

    test "parse returns error if handle string is empty" {
        try std.testing.expectError(error.EmptyTagHandle, parse(""));
    }
    test "parse returns error if handle is invalid" {
        try std.testing.expectError(error.InvalidTagHandle, parse("foo"));
    }
    test "parse returns primary tag handle" {
        try std.testing.expectEqual(TagHandle.primary, parse("!"));
    }
    test "parse returns secondary tag handle" {
        try std.testing.expectEqual(TagHandle.secondary, parse("!!"));
    }
    test "parse returns error if tag handle name is invalid" {
        try std.testing.expectError(error.InvalidNamedTagHandle, parse("!!!"));
    }
    test "parse returns named tag handle if name is valid" {
        try std.testing.expectEqualDeep(TagHandle {
            .named = "foo",
        }, parse("!foo!"));
    }
};

pub const TagPrefix = union(enum) {
    local: []const u8,
    global: []const u8,

    fn isTagCharacter(c: u8) bool {
        // YAML spec section 5.6, figure [40]
        return switch (c) {
            '#', '$', '%', '&', '\'', '*', '+', '-', '.', '/',
            '0'...'9',
            ':', ';', '=', '?', '@',
            'A'...'Z',
            '_',
            'a'...'z',
            '~' => true,
            else => false,
        };
    }

    pub fn parse(string: []const u8) !TagPrefix {
        if (string.len == 0) return error.EmptyTagPrefix;

        if (string[0] == '!') { // Possibly a local tag prefix
            const maybe_local_prefix = string[1..];
            if (util.isUriString(maybe_local_prefix)) {
                return TagPrefix {
                    .local = maybe_local_prefix,
                };
            } else {
                return error.MalformedLocalTagPrefix;
            }
        } else if (isTagCharacter(string[0])) { // Possibly a global tag prefix
            if (util.isUriString(string[1..])) {
                return TagPrefix {
                    .global = string,
                };
            } else {
                return error.MalformedGlobalTagPrefix;
            }
        } else {
            return error.MalformedTagPrefix;
        }
    }

    test "parse returns error if tag prefix string is empty" {
        try std.testing.expectError(error.EmptyTagPrefix, parse(""));
    }
    test "parse returns error if local prefix contains non-uri character" {
        try std.testing.expectError(error.MalformedLocalTagPrefix, parse("!^"));
    }
    test "parse returns local tag if well-formed" {
        try std.testing.expectEqualDeep(TagPrefix {
            .local = "foo",
        }, parse("!foo"));
    }
    test "parse returns error if global tag begins with non-tag character" {
        try std.testing.expectError(error.MalformedTagPrefix, parse("[foo"));
    }
    test "parse returns error if global tag contains non-uri character" {
        try std.testing.expectError(error.MalformedGlobalTagPrefix, parse("foo^"));
    }
    test "parse returns global tag if well-formed" {
        try std.testing.expectEqualDeep(TagPrefix {
            .global = "foo:bar",
        }, parse("foo:bar"));
    }
};

test {
    _ = TagHandle;
    _ = TagPrefix;
}