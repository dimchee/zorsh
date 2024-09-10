const std = @import("std");

pub const Segment = struct { min: f32, max: f32 };
pub const Collision = struct { usize, usize };
const End = enum { Left, Right };
const Edge = struct { tag: End, index: usize, value: f32 };

const Collisions = std.AutoHashMap(Collision, void);

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
    // const sol = try intersection(allocator, colls);
    // std.mem.sort(Collision, sol.items, {}, struct {
    //     fn lessThan(_: void, x: Collision, y: Collision) bool {
    //         return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]);
    //     }
    // }.lessThan);
    // return sol;
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
