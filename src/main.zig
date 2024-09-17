const std = @import("std");
const providers = @import("providers.zig");
const git = @import("git.zig");
const utils = @import("utils.zig");
const config = @import("config.zig");
const mibu = @import("mibu");
const request = @import("request.zig");
const tmpfile = @import("tmpfile");
const editor = @import("editor.zig");

const stdout = std.io.getStdOut();

const commit_message_max_bytes = 4 * 1024; // 4 KiB

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    const alloc = arena.allocator();
    defer arena.deinit();

    const cli_config_result = try config.parseCliConfig(alloc);
    if (cli_config_result == .Err) {
        try utils.err("{s}\n", .{cli_config_result.Err});
        try stdout.writeAll(config.help_message);
        return 1;
    }
    const cli_config = cli_config_result.Ok;

    if (cli_config.help) {
        try stdout.writeAll(config.help_message);
        return 0;
    }

    if (cli_config.version) {
        try stdout.writeAll("mcm version 0.0.1");
        // TODO
        return 0;
    }

    const config_result = try config.loadConfig(alloc);
    if (config_result == .Err) {
        try utils.err("{s}", .{config_result.Err});
        return 1;
    }
    const conf = config_result.Ok;

    const status = try git.checkGitStatus(alloc);
    switch (status) {
        .NotInstalled => {
            try utils.err("Git not found in PATH, it seems you havn't installed it yet", .{});
            return 1;
        },
        .NotRepository => {
            try utils.err("Not a  git repository. Please run this command from within a git repository", .{});
            return 1;
        },
        .IsDirty => {
            try utils.warn("Unstaged changes detected, they will not be considered by LLM", .{});
        },
        .Passed => {},
    }

    const diff_result = try git.populateGitDiff(alloc, &conf);
    switch (diff_result) {
        .Err => |err| {
            try utils.err("Error while calling `git diff`: {s}", .{err});
            return 1;
        },
        .Ok => |diff| {
            if (diff.len == 0) {
                try utils.err("No changes detected in current git repository", .{});
                return 1;
            }
        },
    }
    const diff = diff_result.Ok;

    try utils.info("Waiting for LLM...", .{});
    const response = try request.requestLLM(alloc, &conf, diff, cli_config.hint);

    try mibu.clear.entire_line(stdout);
    try stdout.writer().print("\r", .{});
    const content = try response.value.display(alloc);
    const full_content = try std.mem.concat(alloc, u8, &.{ content, "\n\n", editor.help_message_footer });

    var dir = try tmpfile.TmpDir.init(alloc, .{});
    defer dir.deinit();

    var file = try tmpfile.TmpFile.init(alloc, .{ .tmp_dir = &dir });
    defer file.deinit();
    try file.f.writeAll(full_content);
    file.close();

    const editor_result = try editor.launchEditorAndWait(alloc, &conf, file.abs_path);
    if (editor_result == .Err) {
        try utils.err("Error while launching editor: {s}", .{editor_result.Err});
        return 1;
    }

    const is_empty = try editor.cleanCommitMessageFile(alloc, file.abs_path);
    if (is_empty) {
        try utils.warn("Operation aborted: commit message is empty", .{});
        return 0;
    }

    const commit_result = try git.commitWithMessageFile(alloc, file.abs_path);
    switch (commit_result) {
        .Err => |err| {
            try utils.err("Error while calling `git commit`: {s}", .{err});
            return 1;
        },
        .Ok => {
            try utils.info("Committed successfully, nice work!", .{});
        },
    }

    return 0;
}
