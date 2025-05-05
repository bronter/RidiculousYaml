const std = @import("std");

const YamlReader = @import("yaml_reader.zig");
const util = @import("util.zig");
const constants = @import("constants.zig");
const tag = @import("tag.zig");

pub const TagDirective = struct {
    handle: tag.TagHandle,
    prefix: tag.TagPrefix,

    fn parse(handle_and_prefix_str: []const u8) !TagDirective {
        if (handle_and_prefix_str.len == 0) return error.EmptyTagDirective;

        const sep_index = std.mem.indexOfAny(u8,
            handle_and_prefix_str,
            constants.S_WHITE
        ) orelse return error.MalformedTagDirective;
        const handle_string = handle_and_prefix_str[0..sep_index];
        const handle = try tag.TagHandle.parse(handle_string);

        const prefix_start = std.mem.indexOfNonePos(u8,
            handle_and_prefix_str,
            sep_index + 1,
            constants.S_WHITE
        ) orelse return error.EmptyTagPrefix;
        const prefix_string = handle_and_prefix_str[prefix_start..];
        const prefix = try tag.TagPrefix.parse(prefix_string);

        return TagDirective {
            .handle = handle,
            .prefix = prefix,
        };
    }

    test "parse returns error if string is empty" {
        try std.testing.expectError(error.EmptyTagDirective, parse(""));
    }
    test "parse returns error if no separator" {
        try std.testing.expectError(error.MalformedTagDirective, parse("!foo!"));
    }
    test "parse returns error if no prefix after separator" {
        try std.testing.expectError(error.EmptyTagPrefix, parse("!foo! "));
    }
    test "parse returns tag directive if well-formed" {
        try std.testing.expectEqualDeep(TagDirective {
            .handle = tag.TagHandle {
                .named = "foo",
            },
            .prefix = tag.TagPrefix {
                .local = "bar:baz",
            },
        }, parse("!foo! !bar:baz"));
    }
};

pub const YamlDirective = struct {
    // The spec doesn't seem to define a max length for the version numbers,
    // but if the YAML Language Development Team releases more than four billion major or minor versions,
    // then I'll revisit this.
    major_version: u32,
    minor_version: u32,

    fn parse(version_str: []const u8) !YamlDirective {
        if (std.mem.indexOfScalar(u8, version_str, '.')) |dot_index| {
            const major_str = version_str[0..dot_index];
            const minor_str = version_str[(dot_index + 1)..];
            const major_version = try util.parseDecimalUnsigned(u32, major_str);
            if (major_version > constants.MAX_SUPPORTED_YAML_MAJOR_VERSION) {
                return error.UnsupportedYamlMajorVersion;
            }
            const minor_version = try util.parseDecimalUnsigned(u32, minor_str);
            // TODO: Is this the way a lib should emit warnings?
            //       Seems weird that a lib would be logging stuff unless you explicitly told it to.
            // if (minor_version > constants.MAX_SUPPORTED_YAML_MINOR_VERSION) {
            //     std.log.warn("YAML minor version {d} greater than supported minor version {d}", .{
            //         minor_version,
            //         constants.MAX_SUPPORTED_YAML_MINOR_VERSION,
            //     });
            // }
            return YamlDirective {
                .major_version = major_version,
                .minor_version = minor_version,
            };
        } else {
            return error.MalformedYamlVersion;
        }
    }

    test "parse returns error if version string is empty" {
        try std.testing.expectError(error.MalformedYamlVersion, parse(""));
    }
    test "parse returns error if version string has no dot separator" {
        try std.testing.expectError(error.MalformedYamlVersion, parse("12"));
        try std.testing.expectError(error.MalformedYamlVersion, parse("1 2"));
    }
    test "parse returns error if major version greater than supported major version" {
        try std.testing.expectError(error.UnsupportedYamlMajorVersion, parse("2.2"));
    }
    test "parse returns version if correctly formatted and supported" {
        try std.testing.expectEqualDeep(YamlDirective {
            .major_version = 1,
            .minor_version = 2,
        }, parse("1.2"));
    }
};

pub const ReservedDirective = struct {
    name: []const u8,
    parameters: []const []const u8,

    // Section 6.8, figures [84] and [85]
    fn isDirectiveNameOrParameter(string: []const u8) bool {
        // FIXME: This obviously only works if we're dealing with a UTF-8 stream
        //        However, YAML supports UTF-8, UTF-16LE, UTF-16BE, UTF-32LE, and UTF-32BE
        var utf8_view = std.unicode.Utf8View.init(string) catch return false;
        var utf8_iter = utf8_view.iterator();

        while (utf8_iter.nextCodepoint()) |c| {
            if (!util.isNonSpaceUnicodeCharacter(c)) {
                return false;
            }
        }

        return true;
    }

    test "isDirectiveNameOrParameter returns true if directive name is valid" {
        try std.testing.expectEqual(true, isDirectiveNameOrParameter("foo"));
    }
    test "isDirectiveNameOrParameter returs false if directive name is invalid" {
        try std.testing.expectEqual(false, isDirectiveNameOrParameter("foo\u{FEFF}bar"));
    }

    fn parse(allocator: std.mem.Allocator, name_str: []const u8, parameters_str: []const u8) !ReservedDirective {
        if (name_str.len == 0) return error.EmptyDirectiveName;
        if (!isDirectiveNameOrParameter(name_str)) return error.InvalidDirectiveName;

        var params = std.ArrayList([]const u8).init(allocator);
        errdefer params.deinit();

        var params_split_iter = std.mem.splitAny(u8, parameters_str, constants.S_WHITE);
        while (params_split_iter.next()) |maybe_param| {
            if (maybe_param.len == 0) continue;
            if (isDirectiveNameOrParameter(maybe_param)) {
                try params.append(maybe_param);
            } else {
                return error.InvalidDirectiveParameter;
            }
        }

        return ReservedDirective {
            .name = name_str,
            .parameters = try params.toOwnedSlice(),
        };
    }

    test "parse returns error if directive name is empty" {
        const alloc = std.testing.allocator;
        try std.testing.expectError(error.EmptyDirectiveName, parse(alloc, "", ""));
    }
    test "parse returns reserved directive even if parameters are empty, as long as the name is valid" {
        const alloc = std.testing.allocator;
        const directive = try parse(alloc, "foo", "");
        try std.testing.expectEqualDeep(ReservedDirective {
            .name = "foo",
            .parameters = &[0] []const u8 {},
        }, directive);
    }
    test "parse returns error if one of the parameters is not valid" {
        const alloc = std.testing.allocator;
        try std.testing.expectError(error.InvalidDirectiveParameter, parse(alloc, "foo", "b\u{FEFF}r baz"));
    }
    test "parse returns reserved directive with parameters populated if given valid parameters" {
        const alloc = std.testing.allocator;
        const directive = try parse(alloc, "foo", "bar \tbaz");
        defer alloc.free(directive.parameters);
        try std.testing.expectEqualDeep(ReservedDirective {
            .name = "foo",
            .parameters = &[2] []const u8 {"bar", "baz"},
        }, directive);
    }
};

pub const DirectiveType = enum {
    yaml,
    tag,
    reserved,
};
pub const Directive = union(DirectiveType) {
    yaml: YamlDirective,
    tag: TagDirective,
    reserved: ReservedDirective,

    // Note that this expects line to start with '%' and that it does *NOT* handle inline comments
    // (comments should be stripped prior to calling this function).
    fn parse(allocator: std.mem.Allocator, line: []const u8) !Directive {
        const directive_line = line[1..];
        const maybe_separator_index = std.mem.indexOfAny(u8,
            directive_line,
            constants.S_WHITE,
        );
        var directive_name: []const u8 = undefined;
        if (maybe_separator_index) |separator_index| {
            const maybe_non_separator_index = std.mem.indexOfNonePos(u8,
                directive_line,
                separator_index + 1,
                constants.S_WHITE,
            );
            if (maybe_non_separator_index) |non_separator_index| {
                if (std.mem.startsWith(u8, directive_line, "YAML")) {
                    return Directive {
                        .yaml = try YamlDirective.parse(directive_line[non_separator_index..]),
                    };
                } else if (std.mem.startsWith(u8, directive_line, "TAG")) {
                    return Directive {
                        .tag = try TagDirective.parse(directive_line[non_separator_index..]),
                    };
                } else {
                    // TODO: Really we should generate some sort of warning when we find reserved directives.
                    return Directive {
                        .reserved = try ReservedDirective.parse(
                            allocator,
                            directive_line[0..separator_index],
                            directive_line[non_separator_index..],
                        ),
                    };
                }
            } else {
                directive_name = directive_line[0..separator_index];
            }
        } else {
            directive_name = directive_line;
        }

        if (std.mem.eql(u8, directive_name, "YAML")) {
            return error.InvalidYamlDirective;
        } else if (std.mem.eql(u8, directive_name, "TAG")) {
            return error.InvalidTagDirective;
        } else {
            // TODO: Warn here
            return Directive {
                .reserved = try ReservedDirective.parse(allocator, directive_name, ""),
            };
        }
    }

    test "parse returns yaml directive when given valid yaml directive string" {
        const alloc = std.testing.allocator;
        const directive = try parse(alloc, "%YAML 1.2");
        try std.testing.expectEqual(.yaml, @as(DirectiveType, directive));
    }
    test "parse returns error when given yaml directive not followed by separator" {
        const alloc = std.testing.allocator;
        try std.testing.expectError(error.InvalidYamlDirective, parse(alloc, "%YAML"));
    }
    test "parse returns error when given yaml directive with nothing after separator" {
        const alloc = std.testing.allocator;
        try std.testing.expectError(error.InvalidYamlDirective, parse(alloc, "%YAML "));
    }
    test "parse returns tag directive when given valid tag directive string" {
        const alloc = std.testing.allocator;
        const directive = try parse(alloc, "%TAG !foo! bar:baz");
        try std.testing.expectEqual(.tag, @as(DirectiveType, directive));
    }
    test "parse returns error when given tag directive not followed by separator" {
        const alloc = std.testing.allocator;
        try std.testing.expectError(error.InvalidTagDirective, parse(alloc, "%TAG"));
    }
    test "parse returns error when given tag directive with nothing after separator" {
        const alloc = std.testing.allocator;
        try std.testing.expectError(error.InvalidTagDirective, parse(alloc, "%TAG "));
    }
    test "parse returns reserved directive when given valid reserved directive with params" {
        const alloc = std.testing.allocator;
        const directive = try parse(alloc, "%foo bar baz");
        try std.testing.expectEqual(.reserved, @as(DirectiveType, directive));
    }
    test "parse returns reserved directive when given valid reserved directive with no params" {
        const alloc = std.testing.allocator;
        const directive = try parse(alloc, "%foo");
        try std.testing.expectEqual(expected: anytype, actual: anytype)
    }
};

// TODO: Is it valid for a directives end marker to not be at the start of a line? Like "   --- #foo"?
//       As far as I can tell from the spec, it isn't.
fn isDirectivesEndMarker(line: []const u8) bool {
    var split = std.mem.splitAny(u8, line, constants.S_WHITE);
    if (split.next()) |maybe_marker| {
        if (std.mem.eql(u8, maybe_marker, "---")) {
            return true;
        }
    }
    return false;
}

test "isDirectivesEndMarker returns true if end marker with no spaces or content after" {
    try std.testing.expect(isDirectivesEndMarker("---"));
}
test "isDirectivesEndMarker returns true if end marker with content after" {
    try std.testing.expect(isDirectivesEndMarker("--- foo: bar #comment"));
}
test "isDirectivesEndMarker returs false if no separator space between marker and content" {
    try std.testing.expect(!isDirectivesEndMarker("----"));
    try std.testing.expect(!isDirectivesEndMarker("---#comment"));
}
test "isDirectivesEndMarker returns false if no end marker" {
    try std.testing.expect(!isDirectivesEndMarker("test"));
}

pub fn parseDirectives(allocator: std.mem.Allocator, yaml_reader: *YamlReader) ![]Directive {
    var yaml_directive_defined = false;
    // Empty lines and comment lines skipped here
    try yaml_reader.advanceToContentLine();

    var directives = std.ArrayList(Directive).init(allocator);
    errdefer directives.deinit();

    while (yaml_reader.current_line) |line| {
        // Inline comments stripped here
        const comments_stripped_line = util.stripInlineComment(line);

        if (comments_stripped_line[0] == '%') {
            const directive = try Directive.parse(comments_stripped_line);
            if (directive == .yaml) {
                if (yaml_directive_defined) {
                    return error.RepeatedYAMLDirective;
                } else {
                    yaml_directive_defined = true;
                }
            }
            directives.append(directive);
            try yaml_reader.advanceToContentLine();
        } else if (isDirectivesEndMarker(comments_stripped_line)) {
            // TODO: It really seems like YamlReader needs to read byte-by-byte and check for these things,
            // rather than just to a delimiter, otherwise we can read past the end of an explicit document,
            // and we can't put those bytes back into the reader, so we have to be smart enough to stop reading there.

            // return directives.toOwnedSlice();
            // Need to handle the fact that a document can start on the same line as a directives end marker,
            // as in, "--- |".
            yaml_reader.current_line = yaml_reader.current_line[3..];
            return error.TODO;
        } else if (directives.items.len == 0) { // Bare document (9.1.3)
            // Don't think this does anything, but just in case.
            defer directives.deinit();

            return [0] Directive {};
        } else { // Directives mixed with content, 
            return error.MalformedDirectives;
        }
    }


}

test "parseDirectives should return directives even if the lines end in comments" {
    return error.TODO;
}
test "parseDirectives should return error if content is mixed with directives" {
    return error.TODO;
}
test "parseDirectives should return empty array if no directives" {
    return error.TODO;
}
test "parseDirectives should return empty array if bare document" {
    return error.TODO;
}
test "parseDirectives should return error if there is more than one YAML directive" {
    return error.TODO;
}

// Make test command notice tests within structs
test {
    _ = YamlDirective;
    _ = TagDirective;
    _ = ReservedDirective;
    _ = Directive;
}