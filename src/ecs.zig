const std = @import("std");

pub fn eql(comptime T: type, a: []const T, b: []const T) bool {
    if (a.len != b.len) return false;
    for (a, b) |a_elem, b_elem| if (!std.meta.eql(a_elem, b_elem)) return false;
    return true;
}
pub fn indexOf(comptime T: type, comptime haystack: []const T, comptime needle: []const T) ?usize {
    var i: usize = 0;
    while (i <= @as(i64, haystack.len) - needle.len) : (i += 1)
        if (eql(T, haystack[i..][0..needle.len], needle)) return i;
    return null;
}
fn nub(comptime T: type, args: []const T) []T {
    var sol = toArray(T, args);
    var len = sol.len;
    for (sol, 0..) |_, i|
        while (i < len and indexOf(T, sol[0..i], &[_]T{sol[i]}) != null) : (len -= 1)
            std.mem.swap(T, &sol[i], &sol[len - 1]);
    return sol[0..len];
}
fn toArray(T: type, comptime args: anytype) [args.len]T {
    var sol: [args.len]T = undefined;
    inline for (args, 0..) |arg, i|
        sol[i] = if (T != @TypeOf(arg)) @compileError("Argument types missmatch") else arg;
    return sol;
}

fn dePointer(T: type) type {
    return switch (@typeInfo(T)) {
        .Pointer => |info| info.child,
        else => T,
    };
}
fn dePointerFields(fields: []const std.builtin.Type.StructField) [fields.len]std.builtin.Type.StructField {
    var sol: [fields.len]std.builtin.Type.StructField = undefined;
    for (fields, 0..) |field, i| {
        sol[i] = field;
        sol[i].type = dePointer(field.type);
    }
    return sol;
}

fn Bundle(components: []const type) type {
    const Elem = std.meta.Tuple(components);
    return struct {
        data: std.MultiArrayList(Elem),
        fn init() @This() {
            return .{ .data = std.MultiArrayList(Elem){} };
        }
        fn ensureTotalCapacity(self: *@This(), arena: *std.heap.ArenaAllocator, capacity: usize) !void {
            try self.data.ensureTotalCapacity(arena.allocator(), capacity);
        }
        fn getFieldTag(component: type) std.meta.FieldEnum(Elem) {
            const msg = "Component not recognised `" ++ @typeName(component) ++ "`";
            const index = comptime indexOf(type, components, &[_]type{component}) orelse @compileError(msg);
            return std.meta.intToEnum(std.meta.FieldEnum(Elem), index) catch unreachable;
        }
        fn add(self: *@This(), x: anytype) void {
            var el: Elem = undefined;
            inline for (std.meta.fields(@TypeOf(x))) |field|
                @field(el, std.meta.fieldInfo(Elem, getFieldTag(field.type)).name) = @field(x, field.name);
            self.data.appendAssumeCapacity(el);
        }
    };
}

fn toField(name: [:0]const u8, T: type) std.builtin.Type.StructField {
    return .{ .name = name, .type = T, .default_value = null, .is_comptime = false, .alignment = 0 };
}
fn ArrayStruct(S: anytype) type {
    const sFields = dePointerFields(std.meta.fields(S));
    var fields: [sFields.len + 1]std.builtin.Type.StructField = undefined;
    fields[0] = toField("len", usize);
    for (sFields, 1..) |field, i|
        fields[i] = toField(field.name, []field.type);
    return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
}
fn Query(bundles: []const []const type, S: type) type {
    const bundlesFiltered = comptime filtered: {
        var sol: [bundles.len][]const type = undefined;
        var len = 0;
        const thisComponents = EcsInternal(bundles).getComponents(&dePointerFields(std.meta.fields(S)));
        for (bundles) |bundle| if (indexOf(type, bundle, &thisComponents)) |_| {
            sol[len] = &toArray(type, bundle);
            len += 1;
        };
        break :filtered toArray([]const type, sol[0..len]);
    };
    const removes = comptime removes: {
        var sol: [bundlesFiltered.len](*const fn (*EcsInternal(bundles), usize) void) = undefined;
        for (bundlesFiltered, 0..) |bundle, i|
            sol[i] = struct {
                fn remove(ecs: *EcsInternal(bundles), ind: usize) void {
                    ecs.getBundle(bundle).data.swapRemove(ind);
                }
            }.remove;
        break :removes sol;
    };
    const QueryIterator = struct {
        bundleIndex: usize,
        nextIndex: usize,
        indices: []ArrayStruct(S),
        pub fn destroy(self: *@This(), ecs: *EcsInternal(bundles)) void {
            if (self.bundleIndex >= bundlesFiltered.len) return;
            if (self.nextIndex > self.indices[self.bundleIndex].len) return;
            self.indices[self.bundleIndex].len -= 1;
            self.nextIndex -= 1;
            removes[self.bundleIndex](ecs, self.nextIndex);
        }
        pub fn next(self: *@This()) ?S {
            if (self.bundleIndex >= bundlesFiltered.len) return null;
            if (self.nextIndex >= self.indices[self.bundleIndex].len) {
                self.bundleIndex += 1;
                self.nextIndex = 0;
                return self.next();
            }
            var s: S = undefined;
            inline for (std.meta.fields(S)) |field| {
                const cur = &@field(self.indices[self.bundleIndex], field.name)[self.nextIndex];
                @field(s, field.name) = if (field.type == dePointer(field.type)) cur.* else cur;
            }
            self.nextIndex += 1;
            return s;
        }
    };
    return struct {
        indices: [bundlesFiltered.len]ArrayStruct(S),
        fn init(ecs: *EcsInternal(bundles)) @This() {
            var indices: [bundlesFiltered.len]ArrayStruct(S) = undefined;
            comptime var i = 0;
            inline for (bundlesFiltered) |components| {
                const slice = ecs.getBundle(components).data.slice();
                indices[i].len = slice.len;
                inline for (dePointerFields(std.meta.fields(S))) |field|
                    @field(indices[i], field.name) =
                        slice.items(Bundle(components).getFieldTag(field.type));
                i += 1;
            }
            return .{ .indices = indices };
        }
        pub fn iterator(self: *@This()) QueryIterator {
            return .{ .bundleIndex = 0, .nextIndex = 0, .indices = &self.indices };
        }
    };
}

fn normalise(T: type, bundles: []const []const T, components: []const T) []T {
    var i = 0;
    var sol = toArray(T, nub(T, components));
    for (bundles) |bundle| for (bundle) |x|
        if (std.mem.indexOfScalarPos(T, &sol, i, x)) |ind| {
            std.mem.swap(T, &sol[i], &sol[ind]);
            i += 1;
        };
    return &sol;
}
fn EcsInternal(bundles: []const []const type) type {
    return struct {
        const Self = @This();
        data: [bundles.len]*anyopaque,
        arena: std.heap.ArenaAllocator,
        pub fn init(allocator: std.mem.Allocator, max_entities: usize) !Self {
            var arena = std.heap.ArenaAllocator.init(allocator);
            var data: [bundles.len]*anyopaque = undefined;
            inline for (bundles, 0..) |components, i| {
                const mem = try arena.allocator().create(Bundle(components));
                mem.* = Bundle(components).init();
                try mem.*.ensureTotalCapacity(&arena, max_entities);
                data[i] = mem;
            }
            return .{ .data = data, .arena = arena };
        }
        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }
        fn getBundle(self: *Self, bundle: []const type) *Bundle(bundle) {
            const index = comptime indexOf([]const type, bundles, &[_][]const type{bundle});
            return @ptrCast(@alignCast(self.data[index orelse @compileError("Bundle not recognised")]));
        }
        fn getComponents(fields: []const std.builtin.Type.StructField) [fields.len]type {
            var components: [fields.len]type = undefined;
            for (fields, 0..) |field, i| components[i] = field.type;
            return toArray(type, normalise(type, bundles, &components));
        }
        pub fn add(self: *Self, x: anytype) void {
            const components = getComponents(std.meta.fields(@TypeOf(x)));
            self.getBundle(&components).add(x);
        }
        pub fn query(self: *Self, S: type) Query(bundles, S) {
            return Query(bundles, S).init(self);
        }
        pub fn format(self: *@This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            inline for (bundles) |bundle| {
                var q = self.query(std.meta.Tuple(bundle));
                var it = q.iterator();
                while (it.next()) |x| {
                    inline for (std.meta.fields(std.meta.Tuple(bundle))) |field| {
                        try writer.print("{s}: ", .{@typeName(field.type)});
                        try writer.print("{} ", .{std.json.fmt(@field(x, field.name), .{})});
                    }
                    try writer.print("\n", .{});
                }
                try writer.print("\n", .{});
            }
        }
    };
}
pub fn Ecs(bundles_raw: anytype) type {
    var bundles: [bundles_raw.len][]const type = undefined;
    for (bundles_raw, 0..) |components_raw, i|
        bundles[i] = &toArray(type, components_raw);
    for (bundles_raw, 0..) |components_unnorm, i|
        bundles[i] = &toArray(type, normalise(type, &bundles, &components_unnorm));
    return EcsInternal(&toArray([]const type, nub([]const type, &bundles)));
}

// Components
const Health = struct { u32 };
const Name = struct { name: []const u8 };
const Damage = struct { u32 };

// Bundles
const Player = .{ Health, Name };
const Enemy = .{ Health, Damage };

test "nub1" {
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 1, 2, 3, 4, 5 },
        &comptime toArray(u8, nub(u8, &[_]u8{ 1, 2, 3, 4, 1, 1, 2, 4, 5, 4 })),
    );
}
test "nub2" {
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 2, 1 },
        &comptime toArray(u8, nub(u8, &[_]u8{ 2, 1, 2, 1, 2, 2, 1, 1, 1, 1, 2 })),
    );
}

test "nub3" {
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 1, 2, 3 },
        &comptime toArray(u8, nub(u8, &[_]u8{ 1, 2, 3, 1 })),
    );
}
test "nub4" {
    try std.testing.expectEqualSlices(
        []const u8,
        &[_][]const u8{ &[_]u8{ 1, 2 }, &[_]u8{ 1, 3 } },
        &comptime toArray([]const u8, nub(
            []const u8,
            &[_][]const u8{ &[_]u8{ 1, 2 }, &[_]u8{ 1, 3 } },
        )),
    );
}
test "normalise1" {
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 1, 2 },
        &comptime toArray(u8, normalise(
            u8,
            &[_][]const u8{&[_]u8{ 1, 2 }},
            &[_]u8{ 2, 1 },
        )),
    );
}

test "normalise2" {
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 2, 5 },
        &comptime toArray(u8, normalise(
            u8,
            &[_][]const u8{ &[_]u8{ 3, 4, 3 }, &[_]u8{ 4, 2, 2, 3, 2, 4, 2, 5, 3 } },
            &[_]u8{ 5, 2, 5, 2 },
        )),
    );
}

test "ecs1" {
    var s = try Ecs(.{ Player, Enemy }).init(std.testing.allocator, 100);
    defer s.deinit();
    s.add(.{ Health{100}, Damage{3} });
    s.add(.{ Health{100}, Name{ .name = "Joe" } });
    s.add(.{ Health{200}, Name{ .name = "Petar" } });
    var q = s.query(struct { Health });
    var it = q.iterator();
    try std.testing.expectEqual(.{Health{100}}, it.next().?);
    try std.testing.expectEqual(.{Health{200}}, it.next().?);
    try std.testing.expectEqual(.{Health{100}}, it.next().?);
    try std.testing.expectEqual(null, it.next());
}
test "ecs2" {
    var s = try Ecs(.{ Player, Enemy }).init(std.testing.allocator, 100);
    defer s.deinit();
    s.add(.{ Health{100}, Damage{3} });
    s.add(.{ Health{100}, Name{ .name = "Joe" } });
    s.add(.{ Health{200}, Name{ .name = "Petar" } });
    var q = s.query(struct { Name });
    var it = q.iterator();
    try std.testing.expectEqual(.{Name{ .name = "Joe" }}, it.next().?);
    try std.testing.expectEqual(.{Name{ .name = "Petar" }}, it.next().?);
    try std.testing.expectEqual(null, it.next());
}
test "ecs3" {
    var s = try Ecs(.{ Player, Enemy }).init(std.testing.allocator, 100);
    defer s.deinit();
    s.add(.{ Health{100}, Damage{3} });
    s.add(.{ Health{100}, Name{ .name = "Joe" } });
    s.add(.{ Health{200}, Name{ .name = "Petar" } });
    {
        var q = s.query(struct { health: *Health });
        var it = q.iterator();
        while (it.next()) |x| x.health[0] += 4;
    }
    {
        var q = s.query(struct { Health });
        var it = q.iterator();
        try std.testing.expectEqual(.{Health{104}}, it.next().?);
        try std.testing.expectEqual(.{Health{204}}, it.next().?);
        try std.testing.expectEqual(.{Health{104}}, it.next().?);
        try std.testing.expectEqual(null, it.next());
    }
}
test "ecs4" {
    var s = try Ecs(.{ Player, .{ Damage, Damage, Health, Damage }, Player, Enemy }).init(std.testing.allocator, 100);
    defer s.deinit();
    s.add(.{ Health{100}, Damage{3} });
    s.add(.{ Health{100}, Name{ .name = "Joe" } });
    s.add(.{ Health{200}, Name{ .name = "Petar" } });
    {
        var q = s.query(struct { health: *Health });
        var it = q.iterator();
        while (it.next()) |x| x.health[0] += 4;
    }
    {
        var q = s.query(struct { Health });
        var it = q.iterator();
        try std.testing.expectEqual(.{Health{104}}, it.next().?);
        try std.testing.expectEqual(.{Health{204}}, it.next().?);
        try std.testing.expectEqual(.{Health{104}}, it.next().?);
        try std.testing.expectEqual(null, it.next());
    }
}
test "ecs5" {
    var s = try Ecs(.{ Player, Enemy }).init(std.heap.page_allocator, 1000);
    defer s.deinit();
    s.add(.{ Health{100}, Damage{3} });
    s.add(.{ Health{100}, Name{ .name = "Joe" } });
    s.add(.{ Health{200}, Name{ .name = "Petar" } });
    s.add(.{ Health{300}, Damage{3} });
    {
        var q = s.query(struct { name: Name, health: *Health });
        var it = q.iterator();
        while (it.next()) |x| {
            if (std.mem.eql(u8, x.name.name, "Joe")) x.health[0] += 3;
        }
    }
    {
        var q = s.query(struct { Health });
        var it = q.iterator();
        try std.testing.expectEqual(.{Health{103}}, it.next().?);
        try std.testing.expectEqual(.{Health{200}}, it.next().?);
        try std.testing.expectEqual(.{Health{100}}, it.next().?);
        try std.testing.expectEqual(.{Health{300}}, it.next().?);
        try std.testing.expectEqual(null, it.next());
    }
}
test "ecs6" {
    var s = try Ecs(.{ Player, Enemy }).init(std.heap.page_allocator, 1000);
    defer s.deinit();
    s.add(.{ Health{100}, Damage{3} });
    s.add(.{ Health{100}, Name{ .name = "Joe" } });
    s.add(.{ Health{200}, Name{ .name = "Petar" } });
    s.add(.{ Health{200}, Name{ .name = "Pavle" } });
    s.add(.{ Health{300}, Damage{3} });
    {
        var q = s.query(struct { name: Name, health: *Health });
        var it = q.iterator();
        while (it.next()) |x| {
            if (std.mem.eql(u8, x.name.name, "Petar")) x.health[0] = 0;
        }
    }
    {
        var q = s.query(struct { Health });
        var it = q.iterator();
        while (it.next()) |x| {
            if (x[0][0] == 0) it.destroy(&s);
        }
    }
    {
        var q = s.query(struct { Name });
        var it = q.iterator();
        try std.testing.expectEqual(.{Name{ .name = "Joe" }}, it.next().?);
        try std.testing.expectEqual(.{Name{ .name = "Pavle" }}, it.next().?);
        try std.testing.expectEqual(null, it.next());
    }
}
