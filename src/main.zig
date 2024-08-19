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
        _ = rg.guiLabel(rl.Rectangle.init(halfX() - 240 / 2, halfY() - 300, 300, 100), &buf);
        if (rg.guiButton(rl.Rectangle.init(halfX() - 500 / 2, halfY(), 500, 100), "Menu") != 0) {
            return .{ .menu = void{} };
        }
        return .{ .finished = score };
    }
    fn gui(self: *const State) !Internal {
        if (rg.guiButton(rl.Rectangle.init(halfX() - 500 / 2, halfY() - 100, 500, 100), "Start") != 0) {
            return .{ .running = try game.World.init(self.allocator) };
        }
        return .{ .menu = void{} };
    }
    fn halfX() f32 {
        return @floatFromInt(@divTrunc(rl.getScreenWidth(), 2));
    }
    fn halfY() f32 {
        return @floatFromInt(@divTrunc(rl.getScreenHeight(), 2));
    }
    fn gameLoop(world: *game.World) !Internal {
        try world.update();
        world.draw();
        var health: f32 = @floatFromInt(world.player.health);
        _ = rg.guiProgressBar(rl.Rectangle.init(halfX() - 100 / 2, halfY() - 120, 100, 20), "", "", &health, 0, game.config.player.health);
        return if (health == 0) .{ .finished = world.player.score } else .{ .running = world.* };
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

    var state = State.init(allocator);

    // rl.disableCursor();
    rl.setTargetFPS(60);
    // rl.setTargetFPS(1);
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.ray_white);

        try state.update();
    }
}
