const std = @import("std");
const toml = @import("zig-toml");
const builtin = @import("builtin");
const utils = @import("utils.zig");

pub const help_message =
    \\MCM - Make Commit Message
    \\
    \\Usage: mcm [OPTIONS]
    \\
    \\Automatically generate a well-formed commit message based on your staged changes,
    \\adhering to the Conventional Commits specification.
    \\
    \\Options:
    \\  -h, --help         Show this help message and exit
    \\  -v, --version      Show the version information and exit
    \\  --hint <message>   Provide additional context or instructions for the commit message
    \\
    \\MCM analyzes your git diff and uses AI to create a commit message. It requires
    \\a properly configured API key in $HOME/.config/mcm/config.toml.
    \\
    \\Examples:
    \\  mcm
    \\  mcm --hint "make it shorter"
    \\  mcm --hint "mention also the dependency updates"
    \\  mcm --hint "the scope should be dns/providers"
    \\
    \\For more information, visit: https://github.com/darkyzhou/mcm
;

pub const CliConfig = struct {
    help: bool = false,
    version: bool = false,
    hint: ?[]const u8 = null,
};

pub fn parseCliConfig(alloc: std.mem.Allocator) !utils.Result(CliConfig, []const u8) {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();

    var config = CliConfig{};
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return .{ .Ok = CliConfig{ .help = true } };
        }

        if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            return .{ .Ok = CliConfig{ .version = true } };
        }

        if (std.mem.eql(u8, arg, "--hint")) {
            config.hint = args.next() orelse {
                return .{ .Err = "--hint requires a value" };
            };
        }

        return .{ .Err = "Unknown argument received" };
    }
    return .{ .Ok = config };
}

const default_system_prompt =
    \\You are an expert Git commit message generator. Analyze the `git diff --staged` output and create a commit message following the Conventional Commits specification.
    \\
    \\Rules:
    \\1. Use the provided JSON schema for your response.
    \\2. The `type` must be one of: feat, fix, docs, style, refactor, perf, test, build, ci, or chore.
    \\3. The `subject` should be a brief, imperative description of the change, without a period at the end.
    \\4. Include `scope` only if the change affects a specific component (e.g., parser, module/sub-module).
    \\5. Use the `body` for additional context or reasoning, preferably in bullet points.
    \\6. Include `footer` for breaking changes or issue references.
    \\7. Breaking changes must be indicated by "BREAKING CHANGE:" at the start of the body or footer.
    \\8. Focus on the overall impact rather than listing every modified line.
    \\
    \\Notes:
    \\- `scope`, `body`, and `footer` are optional.
    \\- Use Markdown formatting when appropriate.
    \\
    \\Example output:
    \\{
    \\  "type": "feat",
    \\  "scope": "parser",
    \\  "subject": "add ability to parse arrays",
    \\  "body": "- Implement array parsing functionality\n- Improve error handling for malformed arrays",
    \\  "footer": "BREAKING CHANGE: `parseString` now returns an array instead of a single value"
    \\}
    \\
    \\Now, analyze the following git diff and generate an appropriate commit message:
;

pub const AppConfig = struct {
    api_key: []const u8,
    base_url: []const u8 = "https://api.openai.com/v1",
    model: []const u8 = "gpt-4o-mini",
    system_prompt: []const u8 = default_system_prompt,

    path_to_editor: ?[]const u8 = null,
    ignored_files: []const []const u8 = &.{
        "*.lock*",
        "*-lock.*",
    },
};

const config_max_size_bytes = 1024 * 1024; // 1 MB
const config_file_name = "config.toml";

pub fn loadConfig(alloc: std.mem.Allocator) !utils.Result(AppConfig, []const u8) {
    const config_path = try getConfigFilePath(alloc);
    defer alloc.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return .{ .Err = "Config file not found. Please create a config file with your API key first" },
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(alloc, config_max_size_bytes);
    defer alloc.free(contents);

    var parser = toml.Parser(AppConfig).init(alloc);
    defer parser.deinit();

    const result = try parser.parseString(contents);
    return .{ .Ok = result.value };
}

fn getConfigFilePath(allocator: std.mem.Allocator) ![]const u8 {
    const home_dir = if (std.posix.getenv("HOME")) |home|
        home
    else
        return error.HomeNotDefined;

    return try std.fs.path.join(allocator, &.{ home_dir, ".config", "mcm", config_file_name });
}
