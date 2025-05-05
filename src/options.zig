pub const EncodingOptions = struct {
    utf8: bool = true,
    utf16le: bool = true,
    utf16be: bool = true,
    utf32le: bool = true,
    utf32be: bool = true,
};

// What the initial capacity of the read buffer is set to
initial_read_capacity: usize = 32768,
// How many bytes to try to read at a time
read_length: 4096,

// Which encodings the parser should support
encodings: EncodingOptions,
