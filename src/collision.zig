const std = @import("std");

const Segment = struct { min: f32, max: f32 };
const Collision = struct { usize, usize };
const End = enum { Left, Right };
const Edge = struct { tag: End, index: usize, value: f32 };

const Collisions = std.AutoHashMap(Collision, void);

fn collisionsToArray(colls: Collisions) !std.ArrayList(Collision) {
    var sol = std.ArrayList(Collision).init(std.heap.page_allocator);
    var iter = colls.keyIterator();
    while (iter.next()) |x| try sol.append(x.*);
    return sol;
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

fn allCollisions(allocator: std.mem.Allocator, axisSegments: anytype) !std.ArrayList(Collision) {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var colls: [axisSegments.len]Collisions = undefined;
    inline for (axisSegments, 0..) |segments, i|
        colls[i] = try getCollisions(arena.allocator(), segments);
    return intersection(allocator, colls);
}

fn getCollisions(allocator: std.mem.Allocator, segments: []const Segment) !Collisions {
    var collisions = Collisions.init(allocator);
    var edges = try std.ArrayList(Edge).initCapacity(allocator, 1000);
    defer edges.deinit();
    for (segments, 0..) |x, i| {
        try edges.append(Edge{ .index = i, .value = x.min, .tag = End.Left });
        try edges.append(Edge{ .index = i, .value = x.max, .tag = End.Right });
    }
    for (0..edges.items.len) |ind| {
        var i = ind;
        while (i > 0) : (i -= 1) {
            const x = &edges.items[i - 1];
            const y = &edges.items[i];
            if (x.value < y.value) break;
            std.mem.swap(Edge, x, y);

            if (x.tag == End.Left and y.tag == End.Right) try collisions.put(.{ x.index, y.index }, void{});
            if (y.tag == End.Left and x.tag == End.Right) _ = collisions.remove(.{ x.index, y.index });
        }
    }
    return collisions;
}

fn printEdges(edges: *const std.ArrayList(Edge)) void {
    std.debug.print("[ ", .{});
    for (edges.items) |e| std.debug.print("{d} ", .{e.value});
    std.debug.print("]\n", .{});
}

test "collisions1" {
    const demo_segments = [_]Segment{
        .{ .min = 2, .max = 4 },
        .{ .min = 1, .max = 3 },
        .{ .min = 0, .max = 5 },
    };

    var sol = try allCollisions(std.testing.allocator, .{&demo_segments});
    defer sol.deinit();
    try std.testing.expectEqualDeep(
        sol.items,
        &[_]Collision{ .{ 2, 0 }, .{ 1, 0 }, .{ 2, 1 } },
    );
}
test "collisions2" {
    const demo_segments = [_]Segment{
        .{ .min = 2.5, .max = 4 },
        .{ .min = 1, .max = 2 },
        .{ .min = 0, .max = 5 },
    };

    var sol = try allCollisions(std.testing.allocator, .{&demo_segments});
    defer sol.deinit();
    try std.testing.expectEqualDeep(
        sol.items,
        &[_]Collision{ .{ 2, 0 }, .{ 2, 1 } },
    );
}

test "collisions3" {
    const demo_segments = [_]Segment{
        .{ .min = 2.5, .max = 4 },
        .{ .min = 1, .max = 2.50001 },
        .{ .min = 0, .max = 5 },
    };

    var sol = try allCollisions(std.testing.allocator, .{&demo_segments});
    defer sol.deinit();
    try std.testing.expectEqualDeep(
        sol.items,
        &[_]Collision{ .{ 2, 0 }, .{ 1, 0 }, .{ 2, 1 } },
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
        sol.items,
        &[_]Collision{ .{ 1, 2 }, .{ 3, 4 } },
    );
}

test "collisions4" {
    const demo_segments = [_]Segment{
        .{ .min = 2.5, .max = 4 },
        .{ .min = 1, .max = 2.50001 },
        .{ .min = 0, .max = 5 },
    };

    var sol = try allCollisions(std.testing.allocator, .{&demo_segments});
    defer sol.deinit();
    try std.testing.expectEqualDeep(
        sol.items,
        &[_]Collision{ .{ 2, 0 }, .{ 1, 0 }, .{ 2, 1 } },
    );
}
