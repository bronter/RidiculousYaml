const std = @import("std");

const constants = @import("constants.zig");

pub fn stripInlineComment(slice: []const u8) []const u8 {
    const comment_start = std.mem.lastIndexOfScalar(u8, slice, '#');
    if (comment_start) |comment_start_index| {
        const stripped_comment = slice[0..comment_start_index];
        const stripped_whitespace = std.mem.trimRight(u8, stripped_comment, constants.S_WHITE);
        if (stripped_whitespace.len < stripped_comment.len) {
            return stripped_whitespace;
        }
    }

    return slice;
}

test "stripInlineComment strips comments off of end of line" {
    const stripped = stripInlineComment("foo: bar \t# Very important");
    try std.testing.expectEqualStrings("foo: bar", stripped);
}

test "stripInlineComment does not strip comment if there is no separator" {
    const stripped = stripInlineComment("foo#bar");
    try std.testing.expectEqualStrings("foo#bar", stripped);
}

test "stripInlineComment returns same slice if there is no comment" {
    const stripped = stripInlineComment("foo");
    try std.testing.expectEqualStrings("foo", stripped);
}

// Basically I need to parse an unsigned integer,
// but it needs to error if any of the characters in the string are not decimal digits.
pub fn parseDecimalUnsigned(comptime T: type, string: []const u8) !T {
    const type_info = @typeInfo(T);
    if (type_info != .int or type_info.int.signedness != .unsigned) {
        @compileError("Expected unsigned integer type");
    }

    if (string.len == 0) {
        // This is what std.fmt.parseUnsigned would return in this case.
        return error.InvalidCharacter;
    }

    var result: T = 0;
    for (string) |c| {
        const digit = try std.fmt.charToDigit(c, 10);

        // I use the functions from std.math since they check for overflow
        result = try std.math.mul(T, result, 10);
        result = try std.math.add(T, result, @as(T, digit));
    }

    return result;
}

test "parseDecimalUnsigend returns error if string is empty" {
    try std.testing.expectError(error.InvalidCharacter, parseDecimalUnsigned(u32, ""));
}
test "parseDecimalUnsigned parses unsigned number with decimal digits" {
    try std.testing.expectEqual(3, parseDecimalUnsigned(u32, "3"));
}

pub fn isWordChar(c: u8) bool {
    return switch (c) {
        '0'...'9', 'A'...'Z', 'a'...'z', '-' => true,
        else => false,
    };
}

pub fn isWordCharString(string: []const u8) bool {
    if (string.len == 0) return false;

    for (string) |c| {
        if (!isWordChar(c)) {
            return false;
        }
    }

    return true;
}

test "isWordCharString returns false if string is empty" {
    try std.testing.expectEqual(false, isWordCharString(""));
}
test "isWordCharString returns true if string only contains word characters" {
    try std.testing.expectEqual(true, isWordCharString("fo0-"));
}
test "isWordCharString returns false if string contains non-word characters" {
    try std.testing.expectEqual(false, isWordCharString("f@@~"));
}

// For some reason what the YAML spec thinks is a valid URI is way different
// than what Zig's std.Uri.parse() thinks is a valid URI.
// Note that this function does not attempt to decode percent-encoded characters
pub fn isUriCharacter(c: u8) bool {
    // YAML spec section 5.6, figure [39]
    return switch (c) {
        '!', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/',
        '0'...'9',
        ':', ';', '=', '?', '@',
        'A'...'Z',
        '[', ']', '_',
        'a'...'z',
        '~' => true,
        else => false,
    };
}

// For percent-encoded characters
fn isPercentEncodingHexCode(string: []const u8) bool {
    if (string.len < 2) return false;
    return std.ascii.isHex(string[0]) and std.ascii.isHex(string[1]);
}

pub fn isUriString(string: []const u8) bool {
    for (string, 0..) |c, index| {
        if (c == '%' and !isPercentEncodingHexCode(string[(index + 1)..])) {
            return false;
        }
        if (!isUriCharacter(c)) {
            return false;
        }
    }

    return true;
}

test "isUriString returns true if correct percent encoding" {
    try std.testing.expectEqual(true, isUriString("fo%6f"));
}
test "isUriString returns false if incorrect percent encoding" {
    try std.testing.expectEqual(false, isUriString("fo%"));
    try std.testing.expectEqual(false, isUriString("fo%6"));
    try std.testing.expectEqual(false, isUriString("fo%z"));
}

pub fn isPrintableUnicodeCharacter(c: u21) bool {
    // Section 5.1, figure [1]
    return switch (c) {
        0x09, // '\t'
        0x0A, // '\n'
        0x0D, // '\r'
        0x20...0x7E, // ASCII printable characters
        0x85, // Next Line (NEL)
        0xA0...0xD7FF, // Basic Multilingual Plane (BMP)
        0xE000...0xFFFD, // Additional Unicode Areas
        0x010000...0x10FFFF, // ???
        => true,
        else => false,
    };
}

pub fn isNonBreakUnicodeCharacter(c: u21) bool {
    // Section 5.4, figure [27]
    return switch (c) {
        0x09, // '\t'
        0x20...0x7E, // ASCII printable characters
        0x85, // Next Line (NEL)
        0xA0...0xD7FF, // Basic Multilingual Plane (BMP)
        0xE000...0xFEFE, // Additional Unicode Areas (exclude 0xFEFF)
        0xFF00...0xFFFD, // Additional Unicode Areas (exclude 0xFEFF)
        0x010000...0x10FFFF, // ???
        => true,
        else => false,
    };
}

pub fn isNonSpaceUnicodeCharacter(c: u21) bool {
    // Section 5.5, figure [34]
    return switch (c) {
        0x21...0x7E, // ASCII printable characters (exclude 0x20)
        0x85, // Next Line (NEL)
        0xA0...0xD7FF, // Basic Multilingual Plane (BMP)
        0xE000...0xFEFE, // Additional Unicode Areas (exclude 0xFEFF)
        0xFF00...0xFFFD, // Additional Unicode Areas (exclude 0xFEFF)
        0x010000...0x10FFFF, // ???
        => true,
        else => false,
    };
}