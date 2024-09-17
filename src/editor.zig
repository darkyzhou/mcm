const std = @import("std");
const config = @import("config.zig");
const utils = @import("utils.zig");

pub const help_message_footer =
    \\# Above is the commit message generated by the AI.
    \\# - To accept the message: Save the file and exit. You can make changes if needed.
    \\# - To reject the message and terminate the program: Delete the entire message.
;

pub fn launchEditorAndWait(alloc: std.mem.Allocator, conf: *const config.AppConfig, path: []const u8) !utils.Result(void, []const u8) {
    const editor_result = try getEditorCommand(conf);
    switch (editor_result) {
        .Err => |err| {
            return .{ .Err = err };
        },
        .Ok => {},
    }
    const editor = editor_result.Ok;

    var child = std.process.Child.init(&.{ editor, path }, alloc);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();
    if (term == .Exited and term.Exited == 0) {
        return .Ok;
    }

    return .{ .Err = "Error while running editor process" };
}

pub fn cleanCommitMessageFile(alloc: std.mem.Allocator, path: []const u8) !bool {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
    defer file.close();

    var content = std.ArrayList(u8).init(alloc);
    defer content.deinit();

    var buf: [4096]u8 = undefined;
    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        if (trimmed.len <= 0) {
            try content.append('\n');
            continue;
        }

        if (trimmed[0] == '#') {
            continue;
        }

        try content.appendSlice(trimmed);
        try content.append('\n');
    }

    const new_content = std.mem.trim(u8, content.items, &std.ascii.whitespace);
    try file.setEndPos(0);
    try file.seekTo(0);
    try file.writeAll(new_content);

    return new_content.len == 0;
}

fn getEditorCommand(conf: *const config.AppConfig) !utils.Result([]const u8, []const u8) {
    if (conf.path_to_editor) |path| {
        return .{ .Ok = path };
    }

    const visual = std.posix.getenv("VISUAL");
    if (visual) |value| {
        return .{ .Ok = value };
    }

    const editor = std.posix.getenv("EDITOR");
    if (editor) |value| {
        return .{ .Ok = value };
    }

    return .{ .Err = "No editor found. Please set the EDITOR or VISUAL environment variable, or specify an editor in the configuration" };
}