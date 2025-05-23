const std = @import("std");
const rl = @import("raylib");

fn Queue(maxLen: usize) type {
    return struct {
        bounds: struct { front: usize, end: usize },
        items: [maxLen]usize,
        fn pop(self: *@This()) ?usize {
            if (self.bounds.front >= self.bounds.end) return null;
            self.bounds.front += 1;
            return self.items[self.bounds.front - 1];
        }
        fn push(self: *@This(), x: usize) void {
            if (self.bounds.end >= self.items.len) return;
            self.items[self.bounds.end] = x;
            self.bounds.end += 1;
        }
        fn reset(self: *@This()) void {
            self.bounds = .{ .front = 0, .end = 0 };
        }
    };
}
pub const Cell = enum { Wall, Empty, Player, Spawner };
pub const Position = struct { x: usize, y: usize };
pub fn Map(map: []const u8) type {
    const parsed = items: {
        var items: [map.len]Cell = undefined;
        var len = 0;
        var width: ?usize = null;
        var it = std.mem.tokenizeScalar(u8, map, '\n');
        @setEvalBranchQuota(10000);
        while (it.next()) |line| {
            if (width) |w| if (2 * w != line.len) @compileError("Map width not constant");
            width = line.len / 2;
            var wit = std.mem.window(u8, line, 2, 2);
            while (wit.next()) |w| : (len += 1) {
                items[len] = if (w[0] == '[' and w[1] == ']')
                    Cell.Wall
                else if (w[0] == 'p' and w[1] == 's')
                    Cell.Player
                else if (w[0] == 'z' and w[1] == 's')
                    Cell.Spawner
                else if (w[0] == ' ' and w[1] == ' ')
                    Cell.Empty
                else
                    @compileError("Map cell not recognised");
            }
        }
        var itemsCopy: [len]Cell = undefined;
        std.mem.copyForwards(Cell, &itemsCopy, items[0..len]);
        if (width) |w|
            break :items .{ .items = itemsCopy, .width = w }
        else
            @compileError("Empty Map");
    };
    const parsedWalls = walls: {
        var walls: [parsed.items.len]Position = undefined;
        var ind = 0;
        for (parsed.items, 0..) |cell, i| if (cell == .Wall) {
            walls[ind] = .{ .x = i % parsed.width, .y = i / parsed.width };
            ind += 1;
        };
        var wallsCopy: [ind]Position = undefined;
        std.mem.copyForwards(Position, &wallsCopy, walls[0..ind]);
        break :walls wallsCopy;
    };
    const Hints = struct {
        items: [parsed.items.len]?rl.Vector2,
        pub fn get(self: *const @This(), pos: Position) ?rl.Vector2 {
            const ind = pos.x + pos.y * parsed.width;
            return if (ind < parsed.items.len) self.items[ind] else null;
        }
    };
    return struct {
        pub const items = parsed.items;
        pub const walls = parsedWalls;
        pub fn getHints(target: Position) Hints {
            var hints = [_]?rl.Vector2{null} ** parsed.items.len;
            const nodes: [parsed.items.len]usize = undefined;
            var queue = Queue(parsed.items.len){ .items = nodes, .bounds = .{ .front = 0, .end = 0 } };
            queue.reset();
            queue.push(fromPos(target));
            while (queue.pop()) |i| inline for (.{
                i -% 1,
                i +% 1,
                i -% parsed.width,
                i +% parsed.width,
                i -% 1 -% parsed.width,
                i -% 1 +% parsed.width,
                i +% 1 -% parsed.width,
                i +% 1 +% parsed.width,
            }) |nexti| {
                if (nexti < hints.len and hints[nexti] == null and parsed.items[nexti] != Cell.Wall) {
                    hints[nexti] = direction(toPos(nexti), toPos(i));
                    queue.push(nexti);
                }
            };
            return .{ .items = hints };
        }
        pub fn direction(from: ?Position, to: ?Position) ?rl.Vector2 {
            if (from) |a| if (to) |b| {
                const aa = rl.Vector2.init(@floatFromInt(a.x), @floatFromInt(a.y));
                const bb = rl.Vector2.init(@floatFromInt(b.x), @floatFromInt(b.y));
                return bb.subtract(aa);
            };
            return null;
        }
        pub fn toPos(index: usize) ?Position {
            if (index >= parsed.items.len) return null;
            return .{ .x = index % parsed.width, .y = index / parsed.width };
        }
        pub fn fromPos(vec: Position) usize {
            return vec.x + vec.y * parsed.width;
        }
    };
}
