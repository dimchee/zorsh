const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");
const game = @import("game.zig");

const Score = u32;

const State = struct {
    const Internal = union(enum) {
        menu: void,
        running: game.World,
        finished: Score,
    };
    state: Internal,
    allocator: std.mem.Allocator,
    fn init(allocator: std.mem.Allocator) State {
        return .{ .state = .{ .menu = void{} }, .allocator = allocator };
    }
    fn update(self: *State) !void {
        self.state = switch (self.state) {
            .menu => try self.gui(),
            .running => |*world| try gameLoop(world),
            .finished => |score| try finished(score),
        };
    }
    fn finished(score: Score) !Internal {
        var buf: [24:0]u8 = undefined;
        _ = try std.fmt.bufPrintZ(&buf, "Score: {d:<4}", .{score});
        _ = rg.guiLabel(rl.Rectangle.init(width() / 2 - 240 / 2, height() / 2 - 300, 300, 100), &buf);
        if (rg.guiButton(rl.Rectangle.init(width() / 2 - 500 / 2, height() / 2, 500, 100), "Menu") != 0) {
            return .{ .menu = void{} };
        }
        return .{ .finished = score };
    }
    fn gui(self: *const State) !Internal {
        if (rg.guiButton(rl.Rectangle.init(width() / 2 - 500 / 2, height() / 2 - 100, 500, 100), "Start") != 0) {
            return .{ .running = try game.World.init(self.allocator) };
        }
        return .{ .menu = void{} };
    }
    fn width() f32 {
        return @floatFromInt(rl.getScreenWidth());
    }
    fn height() f32 {
        return @floatFromInt(rl.getScreenHeight());
    }
    fn gameLoop(world: *game.World) !Internal {
        var input: game.Input = undefined;
        const bindings = [_]struct { rl.KeyboardKey, rl.Vector2 }{
            .{ rl.KeyboardKey.key_w, .{ .x = 0, .y = 1 } },
            .{ rl.KeyboardKey.key_s, .{ .x = 0, .y = -1 } },
            .{ rl.KeyboardKey.key_a, .{ .x = 1, .y = 0 } },
            .{ rl.KeyboardKey.key_d, .{ .x = -1, .y = 0 } },
        };
        input.movement = for (bindings) |kv| {
            if (rl.isKeyDown(kv[0])) break kv[1];
        } else rl.Vector2{ .x = 0, .y = 0 };
        input.shoot = rl.isMouseButtonDown(rl.MouseButton.mouse_button_left) or rl.isKeyDown(rl.KeyboardKey.key_space);
        input.direction = rl.getMousePosition().subtract(rl.Vector2.init(width() / 2, height() / 2)).normalize();
        try world.update(input);
        world.draw();
        switch (world.getStatus()) {
            .score => |score| {
                return .{ .finished = score };
            },
            .healthPercentage => |health| {
                var h = health;
                _ = rg.guiProgressBar(rl.Rectangle.init(width() / 2 - 100 / 2, height() / 2 - 120, 100, 20), "", "", &h, 0, 1.0);
                return .{ .running = world.* };
            },
        }
    }
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    rl.initWindow(1600, 900, "Zorsh");
    defer rl.closeWindow();
    var font = rl.getFontDefault();
    font.baseSize = 2;
    rg.guiSetFont(font);

    var state = State{
        .state = .{ .running = try game.World.init(allocator) },
        .allocator = allocator,
    };
    // var state = State.init(allocator);

    // rl.disableCursor();
    rl.setTargetFPS(60);
    // rl.setTargetFPS(1);
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.ray_white);

        try state.update();

        var buf: [24:0]u8 = undefined;
        _ = try std.fmt.bufPrintZ(&buf, "FPS: {d:<4}", .{rl.getFPS()});
        rl.drawText(&buf, 20, 20, 20, rl.Color.black);
    }
}
