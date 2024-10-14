const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");
const game = @import("game.zig");
const render = @import("render.zig");

const State = struct {
    const Score = u32;
    const Internal = union(enum) { menu, running: game.World, finished: Score };
    const Msg = union(enum) { toMainMenu, finish: Score, newGame };
    state: Internal,
    allocator: std.mem.Allocator,
    renderData: render.Data,
    fn update(self: *State, msg: ?Msg) !void {
        if (msg) |m| self.state = switch (m) {
            .toMainMenu => .menu,
            .finish => |score| .{ .finished = score },
            .newGame => .{ .running = try game.World.init(self.allocator) },
        };
        switch (self.state) {
            .running => |*world| {
                var input: game.Input = undefined;
                const bindings = [_]struct { rl.KeyboardKey, rl.Vector2 }{
                    .{ rl.KeyboardKey.key_w, .{ .x = 0, .y = 1 } },
                    .{ rl.KeyboardKey.key_s, .{ .x = 0, .y = -1 } },
                    .{ rl.KeyboardKey.key_a, .{ .x = 1, .y = 0 } },
                    .{ rl.KeyboardKey.key_d, .{ .x = -1, .y = 0 } },
                };
                input.movement = rl.Vector2{ .x = 0, .y = 0 };
                for (bindings) |kv| if (rl.isKeyDown(kv[0])) {
                    input.movement = input.movement.add(kv[1]);
                };
                input.movement = input.movement.normalize();
                input.shoot = rl.isMouseButtonDown(rl.MouseButton.mouse_button_left) or rl.isKeyDown(rl.KeyboardKey.key_space);
                input.direction = rl.getMousePosition().subtract(rl.Vector2.init(width() / 2, height() / 2)).normalize();
                try world.update(input);
            },
            else => {},
        }
    }
    fn draw(self: *State) ?Msg {
        rl.beginDrawing();
        defer rl.endDrawing();
        switch (self.state) {
            .menu => {
                rl.clearBackground(rl.Color.ray_white);
                if (rg.guiButton(rl.Rectangle.init(width() / 2 - 500 / 2, height() / 2 - 100, 500, 100), "Start") != 0) return .newGame;
            },
            .finished => |score| {
                rl.clearBackground(rl.Color.ray_white);
                var buf: [24:0]u8 = undefined;
                _ = std.fmt.bufPrintZ(&buf, "Score: {d:<4}", .{score}) catch "ERROR";
                _ = rg.guiLabel(rl.Rectangle.init(width() / 2 - 240 / 2, height() / 2 - 300, 300, 100), &buf);
                if (rg.guiButton(rl.Rectangle.init(width() / 2 - 500 / 2, height() / 2, 500, 100), "Menu") != 0) return .toMainMenu;
            },
            .running => |*world| {
                rl.clearBackground(rl.Color.black);
                switch (world.getStatus()) {
                    .score => |score| return .{ .finish = score },
                    .hp => |health| {
                        render.draw(&world.ecs, &self.renderData);
                        var h = health;
                        _ = rg.guiProgressBar(rl.Rectangle.init(width() / 2 - 100 / 2, height() / 2 - 120, 100, 20), "", "", &h, 0, 1.0);
                    },
                }
                rl.drawFPS(20, 20);
            },
        }
        return null;
    }
    fn width() f32 {
        return @floatFromInt(rl.getScreenWidth());
    }
    fn height() f32 {
        return @floatFromInt(rl.getScreenHeight());
    }
};

pub fn main() anyerror!void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();

    rl.initWindow(1600, 900, "Zorsh");
    defer rl.closeWindow();
    var font = rl.getFontDefault();
    font.baseSize = 2;
    rg.guiSetFont(font);

    var state = State{
        // .state = .{ .running = try game.World.init(allocator) },
        .state = .menu,
        .allocator = std.heap.c_allocator,
        .renderData = render.Data.init(),
    };

    // rl.disableCursor();
    rl.setTargetFPS(60);
    // rl.setTargetFPS(1);
    var msg = @as(?State.Msg, null);
    while (!rl.windowShouldClose()) {
        try state.update(msg);
        msg = state.draw();
    }
}
