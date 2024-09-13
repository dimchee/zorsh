const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");

pub const Segment = struct { min: f32, max: f32 };
pub const Collision = struct { usize, usize };
const Collisions = std.AutoHashMap(Collision, void);
const End = enum { Left, Right };
const Edge = struct { tag: End, index: usize, value: f32 };

pub fn Collider(Shape: type) type {
    return struct { transform: config.Transform, shape: Shape };
}

fn sqr(x: f32) f32 {
    return x * x;
}
pub fn collide(x: anytype, y: anytype) ?rl.Vector2 {
    if (@TypeOf(x) == Collider(config.Circle) and @TypeOf(y) == Collider(config.Circle)) {
        const dif = x.transform.position.subtract(y.transform.position);
        const scale = x.shape.radius + y.shape.radius - dif.length();
        return if (scale > 0) dif.normalize().scale(scale) else null;
    }
    if (@TypeOf(x) == Collider(config.Rectangle) and @TypeOf(y) == Collider(config.Circle)) {
        const sDif = y.transform.position.subtract(x.transform.position);
        const sgn = rl.Vector2.init(if (sDif.x > 0) -1 else 1, if (sDif.y > 0) -1 else 1);
        const dif = rl.Vector2.init(@abs(sDif.x) - x.shape.size.x / 2, @abs(sDif.y) - x.shape.size.y / 2);
        if (sqr(@max(dif.x, 0)) + sqr(@max(dif.y, 0)) < sqr(y.shape.radius)) {
            if (dif.x > 0 and dif.y > 0) return dif.multiply(sgn).normalize().scale(dif.length() - y.shape.radius);
            if (dif.x > 0) return rl.Vector2.init(dif.x - y.shape.radius, 0).multiply(sgn);
            if (dif.y > 0) return rl.Vector2.init(0, dif.y - y.shape.radius).multiply(sgn);
            // return dif.multiply(sgn).normalize().scale(dif.length() + y.shape.radius + 0.001);
            return if (dif.x > dif.y)
                rl.Vector2.init(dif.x - y.shape.radius, 0).multiply(sgn)
            else
                rl.Vector2.init(0, dif.y - y.shape.radius).multiply(sgn);
        }
        return null;
    }
    if (@TypeOf(x) == Collider(config.Circle) and @TypeOf(y) == Collider(config.Rectangle)) {
        return collide(y, x);
    }
    const msg = "Can't collide `" + @typeName(x) + "` and `" + @typeName(y) + "`";
    @compileError(msg);
}

fn intersection(allocator: std.mem.Allocator, colls: anytype) !std.ArrayList(Collision) {
    var sol = std.ArrayList(Collision).init(allocator);
    var it = colls[0].keyIterator();
    while (it.next()) |x| {
        const intersect = inline for (colls) |col| {
            if (!col.contains(x.*)) break false;
        } else true;
        if (intersect) try sol.append(x.*);
    }
    return sol;
}

pub fn collisions(allocator: std.mem.Allocator, axisSegments: anytype) !std.ArrayList(Collision) {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var colls: [axisSegments.len]Collisions = undefined;
    inline for (axisSegments, 0..) |segments, i|
        colls[i] = try getCollisions(arena.allocator(), segments);
    return intersection(allocator, colls);
}

fn getCollisions(allocator: std.mem.Allocator, segments: []const Segment) !Collisions {
    var colls = Collisions.init(allocator);
    var edges = try std.ArrayList(Edge).initCapacity(allocator, 1000);
    defer edges.deinit();
    for (segments, 0..) |x, i| {
        try edges.append(Edge{ .index = i, .value = x.min, .tag = End.Left });
        try edges.append(Edge{ .index = i, .value = x.max, .tag = End.Right });
    }
    std.mem.sort(Edge, edges.items, {}, struct {
        fn lessThan(_: void, x: Edge, y: Edge) bool {
            return x.value < y.value;
        }
    }.lessThan);
    var touching = std.AutoHashMap(usize, void).init(allocator);
    defer touching.deinit();
    for (edges.items) |edge| {
        if (edge.tag == End.Left) {
            var iter = touching.keyIterator();
            while (iter.next()) |other|
                try colls.put(.{ @min(edge.index, other.*), @max(edge.index, other.*) }, void{});
            try touching.put(edge.index, void{});
        } else _ = touching.remove(edge.index);
    }
    return colls;
}

test "collisions1" {
    const demo_segments = [_]Segment{
        .{ .min = 2, .max = 4 },
        .{ .min = 1, .max = 3 },
        .{ .min = 0, .max = 5 },
    };

    var sol = try collisions(std.testing.allocator, .{&demo_segments});
    defer sol.deinit();
    try std.testing.expectEqualDeep(
        // &[_]Collision{ .{ 2, 0 }, .{ 1, 0 }, .{ 2, 1 } },
        &[_]Collision{ .{ 1, 2 }, .{ 0, 1 }, .{ 0, 2 } },
        sol.items,
    );
}
test "collisions2" {
    const demo_segments = [_]Segment{
        .{ .min = 2.5, .max = 4 },
        .{ .min = 1, .max = 2 },
        .{ .min = 0, .max = 5 },
    };

    var sol = try collisions(std.testing.allocator, .{&demo_segments});
    defer sol.deinit();
    try std.testing.expectEqualDeep(
        // &[_]Collision{ .{ 2, 0 }, .{ 2, 1 } },
        &[_]Collision{ .{ 1, 2 }, .{ 0, 2 } },
        sol.items,
    );
}

test "collisions3" {
    const demo_segments = [_]Segment{
        .{ .min = 2.5, .max = 4 },
        .{ .min = 1, .max = 2.50001 },
        .{ .min = 0, .max = 5 },
    };

    var sol = try collisions(std.testing.allocator, .{&demo_segments});
    defer sol.deinit();
    try std.testing.expectEqualDeep(
        // &[_]Collision{ .{ 2, 0 }, .{ 1, 0 }, .{ 2, 1 } },
        &[_]Collision{ .{ 1, 2 }, .{ 0, 1 }, .{ 0, 2 } },
        sol.items,
    );
}
test "intersection" {
    var map1 = Collisions.init(std.testing.allocator);
    var map2 = Collisions.init(std.testing.allocator);
    defer map1.deinit();
    defer map2.deinit();
    try map1.put(.{ 1, 2 }, void{});
    try map1.put(.{ 2, 3 }, void{});
    try map1.put(.{ 3, 4 }, void{});
    try map1.put(.{ 1, 4 }, void{});
    try map2.put(.{ 5, 1 }, void{});
    try map2.put(.{ 3, 4 }, void{});
    try map2.put(.{ 1, 2 }, void{});
    try map2.put(.{ 3, 3 }, void{});

    var sol = try intersection(std.testing.allocator, .{ map1, map2 });
    defer sol.deinit();
    try std.testing.expectEqualDeep(
        &[_]Collision{ .{ 1, 2 }, .{ 3, 4 } },
        sol.items,
    );
}

test "collisions4" {
    const demo_segments = [_]Segment{
        .{ .min = 2.5, .max = 4 },
        .{ .min = 1, .max = 2.50001 },
        .{ .min = 0, .max = 5 },
    };

    var sol = try collisions(std.testing.allocator, .{&demo_segments});
    defer sol.deinit();
    try std.testing.expectEqualDeep(
        // &[_]Collision{ .{ 2, 0 }, .{ 1, 0 }, .{ 2, 1 } },
        &[_]Collision{ .{ 1, 2 }, .{ 0, 1 }, .{ 0, 2 } },
        sol.items,
    );
}
test "collisions5" {
    const xs = [_]Segment{ .{ .min = 4, .max = 5 }, .{ .min = 4.5, .max = 5.5 } };
    const ys = [_]Segment{ .{ .min = 10, .max = 11 }, .{ .min = 9.5, .max = 10.5 } };
    var sol = try collisions(std.testing.allocator, .{ &xs, &ys });
    defer sol.deinit();
    try std.testing.expectEqualDeep(
        &[_]Collision{.{ 0, 1 }},
        sol.items,
    );
}
