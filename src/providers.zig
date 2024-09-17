const std = @import("std");

pub const OpenAIChatRequest = struct {
    model: []const u8,
    messages: []const OpenAIChatMessage,
    max_completion_tokens: u32,
    temperature: f32,
    response_format: ?OpenAIResponseFormat,
};

pub const openai_response_format_type_json_schema = "json_schema";

pub const OpenAIResponseFormat = struct {
    type: []const u8,
    json_schema: ?OpenAIResponseFormatJsonSchema = null,
};

pub const OpenAIResponseFormatJsonSchema = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    schema: std.json.Value,
    strict: bool,
};

pub const OpenAIChatMessage = struct {
    role: []const u8,
    content: []const u8,
};

pub const openai_chat_message_role_system = "system";
pub const openai_chat_message_role_user = "user";
pub const openai_chat_message_role_assistant = "assistant";

pub const OpenAIResponse = struct {
    choices: []const OpenAIResponseChoice,
};

pub const OpenAIResponseChoice = struct {
    message: OpenAIResponseChoiceMessage,
    finish_reason: []const u8,
};

pub const OpenAIHttpError = error{
    BAD_REQUEST,
    UNAUTHORIZED,
    FORBIDDEN,
    NOT_FOUND,
    TOO_MANY_REQUESTS,
    INTERNAL_SERVER_ERROR,
    SERVICE_UNAVAILABLE,
    GATEWAY_TIMEOUT,
    UNKNOWN,
};

pub const OpenAIResponseChoiceMessage = struct {
    content: []const u8,
};

const openai_chat_completion_path = "chat/completions";
const openai_reponse_max_size_bytes = 64 * 1024; // 64 KiB

pub const OpenAIChatFinishReason = enum(u8) {
    Stop,
    Length,
    ContentFilter,
    Unknown,
};

pub const ChatCompletionResult = struct {
    content: []const u8,
    finish_reason: OpenAIChatFinishReason,
};

pub fn requestOpenAIChatCompetion(
    parent_alloc: std.mem.Allocator,
    client: *std.http.Client,
    base_url: []const u8,
    api_key: []const u8,
    model: []const u8,
    messages: []const OpenAIChatMessage,
    temperature: f32,
    max_tokens: u32,
    response_format: ?OpenAIResponseFormat,
) !ChatCompletionResult {
    var arena = std.heap.ArenaAllocator.init(parent_alloc);
    defer arena.deinit();
    const alloc = arena.allocator();

    const url_string = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ base_url, openai_chat_completion_path });
    const url = try std.Uri.parse(url_string);

    const header_authorization = try std.fmt.allocPrint(alloc, "Bearer {s}", .{api_key});

    const headers = std.http.Client.Request.Headers{
        .content_type = std.http.Client.Request.Headers.Value{
            .override = "application/json",
        },
        .authorization = std.http.Client.Request.Headers.Value{
            .override = header_authorization,
        },
    };

    const body = try std.json.stringifyAlloc(alloc, OpenAIChatRequest{
        .model = model,
        .messages = messages,
        .temperature = temperature,
        .max_completion_tokens = max_tokens,
        .response_format = response_format,
    }, .{});

    var server_header_buffer: [16 * 1024]u8 = undefined;
    var request = try client.open(.POST, url, .{
        .server_header_buffer = &server_header_buffer,
        .headers = headers,
    });
    request.transfer_encoding = .chunked;
    defer request.deinit();

    try request.send();
    try request.writeAll(body);
    try request.finish();
    try request.wait();

    if (request.response.status != .ok) {
        return mapError(request.response.status);
    }

    const data = try request.reader().readAllAlloc(alloc, openai_reponse_max_size_bytes);
    const response = try std.json.parseFromSlice(OpenAIResponse, alloc, data, .{ .ignore_unknown_fields = true });
    return ChatCompletionResult{
        .content = response.value.choices[0].message.content,
        .finish_reason = mapFinishReason(response.value.choices[0].finish_reason),
    };
}

fn mapError(status: std.http.Status) OpenAIHttpError {
    const result = switch (status) {
        .bad_request => OpenAIHttpError.BAD_REQUEST,
        .unauthorized => OpenAIHttpError.UNAUTHORIZED,
        .forbidden => OpenAIHttpError.FORBIDDEN,
        .not_found => OpenAIHttpError.NOT_FOUND,
        .too_many_requests => OpenAIHttpError.TOO_MANY_REQUESTS,
        .internal_server_error => OpenAIHttpError.INTERNAL_SERVER_ERROR,
        .service_unavailable => OpenAIHttpError.SERVICE_UNAVAILABLE,
        .gateway_timeout => OpenAIHttpError.GATEWAY_TIMEOUT,
        else => OpenAIHttpError.UNKNOWN,
    };
    return result;
}

fn mapFinishReason(reason: []const u8) OpenAIChatFinishReason {
    if (std.mem.eql(u8, reason, "stop")) {
        return OpenAIChatFinishReason.Stop;
    }

    if (std.mem.eql(u8, reason, "length")) {
        return OpenAIChatFinishReason.Length;
    }

    if (std.mem.eql(u8, reason, "content_filter")) {
        return OpenAIChatFinishReason.ContentFilter;
    }

    return OpenAIChatFinishReason.Unknown;
}
