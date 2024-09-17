const std = @import("std");
const config = @import("config.zig");
const providers = @import("providers.zig");

const llm_json_schema =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "type": {
    \\      "type": "string",
    \\      "enum": ["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore"],
    \\      "description": "The type of change"
    \\    },
    \\    "scope": {
    \\      "type": "string",
    \\      "description": "The scope of the change (optional by leaving it empty)"
    \\    },
    \\    "subject": {
    \\      "type": "string",
    \\      "description": "A short, imperative description of the change"
    \\    },
    \\    "body": {
    \\      "type": "string",
    \\      "description": "A more detailed explanation of the change (optional by leaving it empty)"
    \\    },
    \\    "footer": {
    \\      "type": "string",
    \\      "description": "Used for referencing issue tracker IDs or breaking changes (optional by leaving it empty)"
    \\    }
    \\  },
    \\  "required": ["type", "scope", "subject", "body", "footer"],
    \\  "additionalProperties": false
    \\}
;

const llm_temperature = 0;
const llm_max_tokens = 200;

const LLMCommitMessageResponse = struct {
    type: []const u8,
    scope: ?[]const u8 = null,
    subject: []const u8,
    body: ?[]const u8 = null,
    footer: ?[]const u8 = null,

    pub fn display(self: *const LLMCommitMessageResponse, alloc: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(alloc);
        errdefer result.deinit();

        try result.appendSlice(self.type);

        if (self.scope) |scope| {
            try result.appendSlice("(");
            try result.appendSlice(scope);
            try result.appendSlice(")");
        }

        try result.appendSlice(": ");
        try result.appendSlice(self.subject);

        if (self.body) |body| {
            try result.appendSlice("\n\n");
            try result.appendSlice(body);
        }

        if (self.footer) |footer| {
            try result.appendSlice("\n\n");
            try result.appendSlice(footer);
        }

        return result.toOwnedSlice();
    }
};

fn populate_user_message(alloc: std.mem.Allocator, diff: []const u8, hint: ?[]const u8) ![]const u8 {
    if (hint == null) {
        return diff;
    }

    var message = std.ArrayList(u8).init(alloc);
    errdefer message.deinit();

    try message.appendSlice("----- Following are the changes -----");
    try message.appendSlice(diff);
    try message.appendSlice("----- Following is the hint, pay attention to its requirement ------");
    try message.appendSlice(hint.?);

    return try message.toOwnedSlice();
}

pub fn requestLLM(
    parent_alloc: std.mem.Allocator,
    conf: *const config.AppConfig,
    diff: []const u8,
    hint: ?[]const u8,
) !std.json.Parsed(LLMCommitMessageResponse) {
    var arena = std.heap.ArenaAllocator.init(parent_alloc);
    defer arena.deinit();
    const alloc = arena.allocator();

    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    const messages = [_]providers.OpenAIChatMessage{
        providers.OpenAIChatMessage{
            .role = providers.openai_chat_message_role_system,
            .content = conf.system_prompt,
        },
        providers.OpenAIChatMessage{
            .role = providers.openai_chat_message_role_user,
            .content = try populate_user_message(alloc, diff, hint),
        },
    };

    const parsed = std.json.parseFromSlice(std.json.Value, alloc, llm_json_schema, .{}) catch unreachable;
    const response_format = providers.OpenAIResponseFormat{
        .type = providers.openai_response_format_type_json_schema,
        .json_schema = providers.OpenAIResponseFormatJsonSchema{
            .name = "response",
            .schema = parsed.value,
            .strict = true,
        },
    };

    const result = try providers.requestOpenAIChatCompetion(
        alloc,
        &client,
        conf.base_url,
        conf.api_key,
        conf.model,
        &messages,
        llm_temperature,
        llm_max_tokens,
        response_format,
    );
    // TODO: handle result.reason

    return try std.json.parseFromSlice(
        LLMCommitMessageResponse,
        alloc,
        result.content,
        .{ .ignore_unknown_fields = true },
    );
}
