const std = @import("std");
const mibu = @import("mibu");
const tmpfile = @import("tmpfile");

pub fn Result(comptime O: type, comptime E: type) type {
    return union(enum) {
        Ok: O,
        Err: E,
    };
}

pub const LogLevel = enum {
    Debug,
    Info,
    Warn,
    Error,
};

pub fn log(level: LogLevel, comptime fmt: []const u8, args: anytype) !void {
    const stdout = std.io.getStdOut();
    const writer = stdout.writer();

    const prefix = switch (level) {
        .Debug => "DEBUG",
        .Info => "INFO",
        .Warn => "WARN",
        .Error => "ERROR",
    };

    const color = switch (level) {
        .Debug => mibu.color.print.fg(.cyan),
        .Info => mibu.color.print.fg(.green),
        .Warn => mibu.color.print.fg(.yellow),
        .Error => mibu.color.print.fg(.red),
    };

    try writer.print("{s}{s}{s} " ++ fmt ++ "\n", .{ color, prefix, mibu.color.print.reset } ++ args);
}

pub fn debug(comptime fmt: []const u8, args: anytype) !void {
    try log(.Debug, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) !void {
    try log(.Info, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) !void {
    try log(.Warn, fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) !void {
    try log(.Error, fmt, args);
}
