const std = @import("std");
const builtin = @import("builtin");

pub const Encoding = enum {
    utf32,
    utf16,
    utf8,
};

pub const EncodingInfo = struct {
    encoding: Encoding,
    endian: std.builtin.Endian,
};
pub const BOMInfo = struct {
    encoding_info: EncodingInfo,
    bom_length: usize,
};

pub fn charType(comptime encoding_info: EncodingInfo) type {
    return switch (encoding_info.encoding) {
        .utf8 => u8,
        .utf16 => u16,
        .utf32 => u32,
    };
}

fn u8ArrayToU32Array(comptime n_u32: usize, bytes: [n_u32 * 4]u8) [n_u32]u32 {
    return @as(*[n_u32]u32, @constCast(@ptrCast(@alignCast(&bytes)))).*;
}
test "u8ArrayToU32Array converts the slices without messing up any of the data" {
    try std.testing.expectEqualSlices(u32,
        &[3]u32 {
            0x55555555,
            0xAAAAAAAA,
            0xCCCCCCCC,
        },
        &u8ArrayToU32Array(3, [3 * 4]u8 {
            0x55, 0x55, 0x55, 0x55,
            0xAA, 0xAA, 0xAA, 0xAA,
            0xCC, 0xCC, 0xCC, 0xCC,
        }),
    );
}

pub fn determineEncodingAndByteOrder(maybe_bom: [4]u8) BOMInfo {
    // We want to view the data as a u32, so do some pointer magic to make it so.
    const maybe_bom_u32: u32 = @as(*u32, @constCast(@ptrCast(@alignCast(&maybe_bom)))).*;
    const maybe_bom_vec: @Vector(10, u32) = @splat(maybe_bom_u32);

    const targets: @Vector(10, u32) = u8ArrayToU32Array(10, [10 * 4]u8 {
        0x00, 0x00, 0xFE, 0xFF,
        0x00, 0x00, 0x00, 0x00,
        0xFF, 0xFE, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0xFE, 0xFF, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0xFF, 0xFE, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0xEF, 0xBB, 0xBF, 0x00,
        0x00, 0x00, 0x00, 0x00,
    });
    const masks: @Vector(10, u32) = u8ArrayToU32Array(10, [10 * 4]u8 {
        0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF,
        0x00, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0x00, 0x00,
        0xFF, 0x00, 0x00, 0x00,
        0xFF, 0xFF, 0x00, 0x00,
        0x00, 0xFF, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0x00,
        0x00, 0x00, 0x00, 0x00,
    });

    const masked = maybe_bom_vec & masks;
    const eql = masked == targets;

    // This is mostly what std.simd.firstTrue does, but we will always have at least one true,
    // so we can eliminate the check for the case where none of the values are true.
    const all_max: @Vector(10, u4) = @splat(~@as(u4, 0));
    const index_vec = @select(u4, eql, std.simd.iota(u4, 10), all_max);
    const encoding_index = @as(usize, @reduce(.Min, index_vec));


    const target_endian = builtin.cpu.arch.endian();
    const encodings = [_] BOMInfo {
        BOMInfo {
            .encoding_info = EncodingInfo {
                .encoding = .utf32,
                .endian = .big,
            },
            .bom_length = 4,
        },
        BOMInfo {
            .encoding_info = EncodingInfo {
                .encoding = .utf32,
                .endian = .big,
            },
            .bom_length = 0,
        },
        BOMInfo {
            .encoding_info = EncodingInfo {
                .encoding = .utf32,
                .endian = .little,
            },
            .bom_length = 4,
        },
        BOMInfo {
            .encoding_info = EncodingInfo {
                .encoding = .utf32,
                .endian = .little,
            },
            .bom_length = 0,
        },
        BOMInfo {
            .encoding_info = EncodingInfo {
                .encoding = .utf16,
                .endian = .big,
            },
            .bom_length = 2,
        },
        BOMInfo {
            .encoding_info = EncodingInfo {
                .encoding = .utf16,
                .endian = .big,
            },
            .bom_length = 0,
        },
        BOMInfo {
            .encoding_info = EncodingInfo {
                .encoding = .utf16,
                .endian = .little,
            },
            .bom_length = 2,
        },
        BOMInfo {
            .encoding_info = EncodingInfo {
                .encoding = .utf16,
                .endian = .little,
            },
            .bom_length = 0,
        },
        BOMInfo {
            .encoding_info = EncodingInfo {
                .encoding = .utf8,
                .endian = target_endian,
            },
            .bom_length = 3,
        },
        BOMInfo {
            .encoding_info = EncodingInfo {
                .encoding = .utf8,
                .endian = target_endian,
            },
            .bom_length = 0,
        },
    };

    return encodings[encoding_index];
}

test "determineEncodingAndByteOrder correctly detects UTF-32BE with explicit BOM" {
    const text = [_]u8 {0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 'A'};
    try std.testing.expectEqualDeep(BOMInfo {
        .encoding_info = EncodingInfo {
            .encoding = .utf32,
            .endian = .big,
        },
        .bom_length = 4,
    }, determineEncodingAndByteOrder(text[0..4].*));
}
test "determineEncodingAndByteOrder correctly detects UTF-32BE with first character" {
    const text = [_]u8 {0x00, 0x00, 0x00, 'A', 0x00, 0x00, 0x00, 'B'};
    try std.testing.expectEqualDeep(BOMInfo {
        .encoding_info = EncodingInfo {
            .encoding = .utf32,
            .endian = .big,
        },
        .bom_length = 0,
    }, determineEncodingAndByteOrder(text[0..4].*));
}

test "determineEncodingAndByteOrder correctly detects UTF-32LE with explicit BOM" {
    const text = [_]u8 {0xFF, 0xFE, 0x00, 0x00, 'A', 0x00, 0x00, 0x00};
    try std.testing.expectEqualDeep(BOMInfo {
        .encoding_info = EncodingInfo {
            .encoding = .utf32,
            .endian = .little,
        },
        .bom_length = 4,
    }, determineEncodingAndByteOrder(text[0..4].*));
}
test "determineEncodingAndByteOrder correctly detects UTF-32LE with first character" {
    const text = [_]u8 {'A', 0x00, 0x00, 0x00, 'B', 0x00, 0x00, 0x00};
    try std.testing.expectEqualDeep(BOMInfo {
        .encoding_info = EncodingInfo {
            .encoding = .utf32,
            .endian = .little,
        },
        .bom_length = 0,
    }, determineEncodingAndByteOrder(text[0..4].*));
}

test "determineEncodingAndByteOrder correctly detects UTF-16BE with explicit BOM" {
    const text = [_]u8 {0xFE, 0xFF, 0x00, 'A', 0x00, 'B', 0x00, 'C'};
    try std.testing.expectEqualDeep(BOMInfo {
        .encoding_info = EncodingInfo {
            .encoding = .utf16,
            .endian = .big,
        },
        .bom_length = 2,
    }, determineEncodingAndByteOrder(text[0..4].*));
}
test "determineEncodingAndByteOrder correctly detects UTF-16BE with first character" {
    const text = [_]u8 {0x00, 'A', 0x00, 'B', 0x00, 'C', 0x00, 'D'};
    try std.testing.expectEqualDeep(BOMInfo {
        .encoding_info = EncodingInfo {
            .encoding = .utf16,
            .endian = .big,
        },
        .bom_length = 0,
    }, determineEncodingAndByteOrder(text[0..4].*));
}

test "determineEncodingAndByteOrder correctly detects UTF-16LE with explicit BOM" {
    const text = [_]u8 {0xFF, 0xFE, 'A', 0x00, 'B', 0x00, 'C', 0x00};
    try std.testing.expectEqualDeep(BOMInfo {
        .encoding_info = EncodingInfo {
            .encoding = .utf16,
            .endian = .little,
        },
        .bom_length = 2,
    }, determineEncodingAndByteOrder(text[0..4].*));
}
test "determineEncodingAndByteOrder correctly detects UTF-16LE with first character" {
    const text = [_]u8 {'A', 0x00, 'B', 0x00, 'C', 0x00, 'D', 0x00};
    try std.testing.expectEqualDeep(BOMInfo {
        .encoding_info = EncodingInfo {
            .encoding = .utf16,
            .endian = .little,
        },
        .bom_length = 0,
    }, determineEncodingAndByteOrder(text[0..4].*));
}

test "determineEncodingAndByteOrder correctly detects UTF-8 with explicit BOM" {
    const text = [_]u8 {0xEF, 0xBB, 0xBF, 'A', 'B', 'C', 'D', 'E'};
    try std.testing.expectEqualDeep(BOMInfo {
        .encoding_info = EncodingInfo {
            .encoding = .utf8,
            .endian = builtin.cpu.arch.endian(),
        },
        .bom_length = 3,
    }, determineEncodingAndByteOrder(text[0..4].*));
}
test "determineEncodingAndByteOrder defaults to UTF-8 when no BOM is present" {
    const text = [_]u8 {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'};
    try std.testing.expectEqualDeep(BOMInfo {
        .encoding_info = EncodingInfo {
            .encoding = .utf8,
            .endian = builtin.cpu.arch.endian(),
        },
        .bom_length = 0,
    }, determineEncodingAndByteOrder(text[0..4].*));
}

fn calcUtf16Len(comptime utf8_text: []const u8) usize {
    return comptime std.unicode.calcUtf16LeLenImpl(
        utf8_text,
        .cannot_encode_surrogate_half
    ) catch |err| @compileError(@errorName(err));
}

fn calcUtf32Len(comptime utf8_text: []const u8) usize {
    return comptime std.unicode.utf8CountCodepoints(utf8_text) catch |err| @compileError(@errorName(err));
}

fn calcEncodedLength(comptime utf8_text: []const u8, comptime encoding_info: EncodingInfo) usize {
    return switch (encoding_info.encoding) {
        .utf8 => utf8_text.len,
        .utf16 => calcUtf16Len(utf8_text),
        .utf32 => calcUtf32Len(utf8_text),
    };
}

test "calcEncodedLength works for utf-8" {
    try std.testing.expectEqual("𰻞𰻞麵".len, calcEncodedLength("𰻞𰻞麵", EncodingInfo {
        .encoding = .utf8,
        .endian = .little,
    }));
}
test "calcEncodedLength works for utf-16" {
    // Since '𰻞' (0x30EDE) is greater than 0x10000 it has to be encoded using surrogates, so it takes up two u16s.
    // '麵' (0x9EB5) does not require surrogates, so it only takes up one u16.
    // Therefore, 2 + 2 + 1 = 5
    try std.testing.expectEqual(5, calcEncodedLength("𰻞𰻞麵", EncodingInfo {
        .encoding = .utf16,
        .endian = .little,
    }));
}
test "calcEncodedLength works for utf-32" {
    try std.testing.expectEqual(3, calcEncodedLength("𰻞𰻞麵", EncodingInfo {
        .encoding = .utf32,
        .endian = .little,
    }));
}

fn encodedType(comptime utf8_text: []const u8, encoding_info: EncodingInfo) type {
    const length = calcEncodedLength(utf8_text, encoding_info);
    return *const [length] charType(encoding_info);
}

fn encodeUtf16(comptime string_literal: []const u8, comptime endian: std.builtin.Endian, comptime output_len: usize) *const [output_len]u16 {
    return comptime blk: {
        var output_buffer = [1]u16 {0} ** output_len;

        const encoded_size = std.unicode.utf8ToUtf16LeImpl(
            &output_buffer,
            string_literal,

            // Normally surrogates occur in pairs,
            // with the first in the range 0xD800-0xDBFF and the second in the range 0xDC00-0xDFFF.
            // If these surrogate halfs are in the wrong order, or we only have one half of the pair,
            // it would be invalid UTF-16
            // (however WTF-16 would allow it and encode the halves as individual characters in the surrogate block).
            // YAML explicitely excludes the surrogate block from its printable character set (section 5.1),
            // so we should not allow lone surrogate halves in any printable string.
            .cannot_encode_surrogate_half
        ) catch |err| @compileError(@errorName(err));
        if (encoded_size != output_len) @compileError("Encoded utf16 length does not match expected length");

        if (endian != .little) {
            for(0..encoded_size) |i| {
                output_buffer[i] = @byteSwap(output_buffer[i]);
            }
        }

        // I don't fully understand why, but the compiler thinks the var is supposed to be runtime if we don't do this.
        const output_buffer_const = output_buffer;
        break :blk &output_buffer_const;
    };
}

fn encodeUtf32(comptime string_literal: []const u8, comptime endian: std.builtin.Endian, comptime output_len: usize) *const [output_len]u32 {
    return comptime blk: {
        var output_buffer = [1]u32 {0} ** output_len;
        const view = std.unicode.Utf8View.initComptime(string_literal);
        var iter = view.iterator();
        var output_index = 0;
        const cpu_same_endian = builtin.cpu.arch.endian() == endian;
        while (iter.nextCodepoint()) |codepoint| {
            if (output_index >= output_len) @compileError("Encoded utf32 length does not match expected length");

            const c = if (cpu_same_endian) @as(u32, codepoint) else @byteSwap(@as(u32, codepoint));
            output_buffer[output_index] = c;
            output_index += 1;
        }

        const output_buffer_const = output_buffer;
        break :blk &output_buffer_const;
    };
}

pub fn encodeLiteral(comptime string_literal: []const u8, comptime encoding_info: EncodingInfo) encodedType(string_literal, encoding_info) {
    // Kind of unfortunate we have to calculate this multiple times,
    // but as far as I can tell there's no way to infer it from the return type,
    // since the type info for generic functions sets the return type to null:
    // https://github.com/ziglang/zig/pull/11188
    // Hopefully the Zig compiler memoizes it 🤷🏼‍♂️
    const output_len = comptime calcEncodedLength(string_literal, encoding_info);

    return switch (encoding_info.encoding) {
        .utf8 => string_literal[0..],
        .utf16 => encodeUtf16(string_literal, encoding_info.endian, output_len),
        .utf32 => encodeUtf32(string_literal, encoding_info.endian, output_len),
    };
}

test "encodeLiteral works for utf-8" {
    try std.testing.expectEqualSlices(u8, "𰻞𰻞麵", encodeLiteral("𰻞𰻞麵", EncodingInfo {
        .encoding = .utf8,
        .endian = .little,
    }));
}
test "encodeLiteral works for utf-16le" {
    const expected_bytes = [5 * 2]u8 {
        0x83, 0xD8, 0xDE, 0xDE, 0x83, 0xD8, 0xDE, 0xDE, 0xB5, 0x9E,
    };
    const expected_u16s: []u16 = @constCast(@ptrCast(@alignCast(&expected_bytes)));
    try std.testing.expectEqualSlices(u16, 
        expected_u16s,
        encodeLiteral("𰻞𰻞麵", EncodingInfo {
            .encoding = .utf16,
            .endian = .little,
        }),
    );
}
test "encodeLiteral works for utf-16be" {
    const expected_bytes = [5 * 2]u8 {
        0xD8, 0x83, 0xDE, 0xDE, 0xD8, 0x83, 0xDE, 0xDE, 0x9E, 0xB5,
    };
    const expected_u16s: []u16 = @constCast(@ptrCast(@alignCast(&expected_bytes)));
    try std.testing.expectEqualSlices(u16, 
        expected_u16s,
        encodeLiteral("𰻞𰻞麵", EncodingInfo {
            .encoding = .utf16,
            .endian = .big,
        }),
    );
}
test "encodeLiteral works for utf-32le" {
    const expected_bytes = [3 * 4]u8 {
        0xDE, 0x0E, 0x03, 0x00, 0xDE, 0x0E, 0x03, 0x00, 0xB5, 0x9E, 0x00, 0x00,
    };
    const expected_u32s: []u32 = @constCast(@ptrCast(@alignCast(&expected_bytes)));
    try std.testing.expectEqualSlices(u32,
        expected_u32s,
        encodeLiteral("𰻞𰻞麵", EncodingInfo {
            .encoding = .utf32,
            .endian = .little,
        }),
    );
}
test "encodeLiteral works for utf-32be" {
    const expected_bytes = [3 * 4]u8 {
        0x00, 0x03, 0x0E, 0xDE, 0x00, 0x03, 0x0E, 0xDE, 0x00, 0x00, 0x9E, 0xB5,
    };
    const expected_u32s: []u32 = @constCast(@ptrCast(@alignCast(&expected_bytes)));
    try std.testing.expectEqualSlices(u32,
        expected_u32s,
        encodeLiteral("𰻞𰻞麵", EncodingInfo {
            .encoding = .utf32,
            .endian = .big,
        }),
    );
}