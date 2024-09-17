const std = @import("std");
const config = @import("config.zig");
const utils = @import("utils.zig");

pub const GitStatus = enum {
    NotInstalled,
    NotRepository,
    IsDirty,
    Passed,
};

pub fn checkGitStatus(alloc: std.mem.Allocator) !GitStatus {
    const version = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "git", "--version" },
    }) catch return .NotInstalled;
    if (version.term != .Exited or version.term.Exited != 0) {
        return .NotInstalled;
    }

    const repo = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "git", "rev-parse", "--is-inside-work-tree" },
    });
    if (repo.term == .Exited and repo.term.Exited != 0) {
        return .NotRepository;
    }

    const unstaged_result = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "git", "diff", "--no-ext-diff", "--quiet" },
    });
    if (unstaged_result.term == .Exited and unstaged_result.term.Exited == 1) {
        return .IsDirty;
    }

    const untracked_result = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "git", "ls-files", "--others", "--exclude-standard", "--directory", "--no-empty-directory", "--error-unmatch", "--", "." },
    });
    if (untracked_result.term == .Exited and untracked_result.term.Exited == 0) {
        return .IsDirty;
    }

    return .Passed;
}

pub fn populateGitDiff(alloc: std.mem.Allocator, conf: *const config.AppConfig) !utils.Result([]const u8, []const u8) {
    var args = std.ArrayList([]const u8).init(alloc);
    defer args.deinit();

    try args.appendSlice(&[_][]const u8{
        "git",
        "--no-pager",
        "diff",
        "--staged",
        "--minimal",
        "--no-color",
        "--function-context",
        "--no-ext-diff",
        "--",
    });

    for (conf.ignored_files) |ignored| {
        try args.append(try std.fmt.allocPrint(alloc, ":(exclude){s}", .{ignored}));
    }

    const result = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = args.items,
    });
    if (result.term == .Exited and result.term.Exited == 0) {
        // TODO: Handle massive output
        return .{ .Ok = std.mem.trim(u8, result.stdout, &std.ascii.whitespace) };
    }

    return .{ .Err = result.stderr };
}

pub fn commitWithMessageFile(alloc: std.mem.Allocator, file_path: []const u8) !utils.Result(void, []const u8) {
    const result = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "git", "commit", "-F", file_path },
    });
    if (result.term == .Exited and result.term.Exited == 0) {
        return .Ok;
    }

    return .{ .Err = result.stderr };
}
