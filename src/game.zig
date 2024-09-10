const rl = @import("raylib");
const std = @import("std");
const collision = @import("collision.zig");
const config = @import("config.zig");

const Position = struct {
    x: i32,
    y: i32,
    fn toVec2(self: *const Position) rl.Vector2 {
        return rl.Vector2.init(@floatFromInt(self.x), @floatFromInt(self.y));
    }
    fn fromVec2(vec: rl.Vector2) Position {
        return .{ .x = @intFromFloat(vec.x + 0.5), .y = @intFromFloat(vec.y + 0.5) };
    }
};
const Cell = enum { Wall, Player, Spawner };
fn mapToCells(allocator: std.mem.Allocator) !std.AutoHashMap(Position, Cell) {
    var cells = std.AutoHashMap(Position, Cell).init(allocator);
    var pos = Position{ .x = 0, .y = 0 };
    var last: u8 = '\n';
    for (config.map) |c| {
        const cell: ?Cell = switch (c) {
            ']' => if (last == '[') Cell.Wall else null,
            's' => switch (last) {
                'p' => Cell.Player,
                'z' => Cell.Spawner,
                else => null,
            },
            else => null,
        };
        if (cell) |t| try cells.put(.{ .x = @divTrunc(pos.x, 2), .y = pos.y }, t);
        last = c;
        pos = if (c == '\n') .{ .x = 0, .y = pos.y + 1 } else .{ .x = pos.x + 1, .y = pos.y };
    }
    return cells;
}

fn getHints(allocator: std.mem.Allocator, target: rl.Vector2, cells: std.AutoHashMap(Position, Cell)) !std.AutoHashMap(Position, Position) {
    var arena = std.heap.ArenaAllocator.init(allocator);
    var sol = std.AutoHashMap(Position, Position).init(arena.allocator());
    var q = std.DoublyLinkedList(struct { from: Position, to: Position }){};
    var nodes: [10000]@TypeOf(q).Node = undefined;
    var ind: u32 = 0;
    var pos = Position.fromVec2(target);
    nodes[ind] = .{ .data = .{ .from = pos, .to = pos } };
    q.prepend(&nodes[ind]);
    ind += 1;
    while (q.pop()) |hint| {
        pos = hint.data.to;
        if (cells.get(pos)) |x|
            if (x == Cell.Wall) continue;
        if (sol.contains(pos)) continue;
        try sol.put(pos, hint.data.from);
        const dxs = [_]i8{ 1, 1, 0, -1, -1, -1, 0, 1 };
        const dys = [_]i8{ 0, 1, 1, 1, 0, -1, -1, -1 };
        for (dxs, dys) |dx, dy| {
            const to = .{ .x = pos.x + dx, .y = pos.y + dy };
            nodes[ind] = .{ .data = .{ .from = pos, .to = to } };
            q.prepend(&nodes[ind]);
            ind += 1;
        }
    }
    return sol;
}

const Status = union(enum) {
    score: u32,
    healthPercentage: f32,
};

pub const Input = struct {
    shoot: bool,
    movement: rl.Vector2,
    direction: rl.Vector2,
};

pub const World = struct {
    score: u32,
    allocator: std.mem.Allocator,
    ecs: config.Ecs,
    cells: std.AutoHashMap(Position, Cell),
    pub fn init(allocator: std.mem.Allocator) !World {
        const cells = try mapToCells(allocator);
        var ecs = try config.Ecs.init(allocator, 1000);
        {
            var it = cells.iterator();
            const pos = while (it.next()) |cell| {
                if (cell.value_ptr.* == Cell.Player)
                    break cell.key_ptr.toVec2();
            } else rl.Vector2.init(0, 0);
            ecs.add(.{ config.Health{config.player.health}, config.Transform{ .position = pos }, config.Gun{ .lastFired = 0 }, config.Circle{ .radius = config.character.radius }, config.PlayerTag{} });
        }
        {
            var it = cells.iterator();
            while (it.next()) |entry| switch (entry.value_ptr.*) {
                .Wall => ecs.add(.{ config.Transform{ .position = entry.key_ptr.toVec2() }, config.Square{ .size = rl.Vector2.init(config.wall.size, config.wall.size) }, config.WallTag{} }),
                .Player => {},
                .Spawner => ecs.add(.{ config.Transform{ .position = entry.key_ptr.toVec2() }, config.NextSpawn{ .time = 0.0 }, config.SpawnerTag{} }),
            };
        }
        return .{ .allocator = allocator, .ecs = ecs, .cells = cells, .score = 0 };
    }
    pub fn getStatus(self: *World) Status {
        var q = self.ecs.query(struct { health: config.Health, tag: config.PlayerTag });
        var it = q.iterator();
        return if (it.next()) |x| .{ .healthPercentage = @as(f32, @floatFromInt(x.health[0])) / config.player.health } else .{ .score = self.score };
    }
    pub fn update(self: *World, input: Input) !void {
        {
            var q = self.ecs.query(struct { transform: config.Transform, nextSpawn: *config.NextSpawn, tag: config.SpawnerTag });
            var it = q.iterator();
            while (it.next()) |spawner| {
                if (rl.getTime() < spawner.nextSpawn.time) continue;
                spawner.nextSpawn.time = rl.getTime() + 1.0 / config.enemy.spawnRate;
                self.ecs.add(.{
                    .health = config.Health{config.enemy.health},
                    .transform = config.Transform{ .position = spawner.transform.position },
                    .shape = config.Circle{ .radius = config.character.radius },
                    .tag = config.EnemyTag{},
                });
            }
        }
        const hints = hints: {
            var q = self.ecs.query(struct { transform: *config.Transform, tag: config.PlayerTag });
            var it = q.iterator();
            var player = it.next().?;
            std.debug.assert(it.next() == null);
            player.transform.position = input.movement
                .scale(config.character.speed)
                .rotate(-input.direction.angle(rl.Vector2.init(0, 1)))
                .add(player.transform.position);
            break :hints try getHints(self.allocator, player.transform.position, self.cells);
        };
        {
            var q = self.ecs.query(struct { transform: *config.Transform, tag: config.EnemyTag });
            var it = q.iterator();
            while (it.next()) |enemy| {
                if (hints.get(Position.fromVec2(enemy.transform.position))) |h| {
                    enemy.transform.position = h.toVec2()
                        .subtract(enemy.transform.position)
                        .normalize().scale(config.character.speed * config.enemy.speedFactor)
                        .add(enemy.transform.position);
                } else {
                    std.log.warn("No hint for enemy at {}", .{enemy.transform.position});
                }
            }
        }
        // TODO bullets going through walls (when one over the other)
        {
            var q = self.ecs.query(struct { transform: *config.Transform, dir: config.Direction });
            var it = q.iterator();
            while (it.next()) |bullet| {
                bullet.transform.position = bullet.transform.position.add(bullet.dir[0].normalize().scale(config.bullet.speed));
            }
        }
        if (input.shoot) {
            var q = self.ecs.query(struct { transform: config.Transform, gun: *config.Gun });
            var it = q.iterator();
            while (it.next()) |player| {
                const isReadyToFire = player.gun.lastFired + 1.0 / config.bullet.rate < rl.getTime();
                if (isReadyToFire) {
                    self.ecs.add(.{
                        config.Transform{ .position = input.direction
                            .scale(config.character.radius + config.bullet.radius)
                            .add(player.transform.position) },
                        config.DeathTime{rl.getTime() + config.bullet.lifetime},
                        config.Direction{input.direction},
                        config.Circle{ .radius = config.bullet.radius },
                        config.BulletTag{},
                    });
                    player.gun.lastFired = rl.getTime();
                }
            }
        }
        {
            var q = self.ecs.query(collision.Collider(config.Circle));
            const coll = collisions: {
                var it = q.iterator();
                var xs = try std.ArrayList(collision.Segment).initCapacity(self.allocator, 100);
                var ys = try std.ArrayList(collision.Segment).initCapacity(self.allocator, 100);
                while (it.next()) |e| {
                    try xs.append(.{ .min = e.transform.position.x - e.shape.radius, .max = e.transform.position.x + e.shape.radius });
                    try ys.append(.{ .min = e.transform.position.y - e.shape.radius, .max = e.transform.position.y + e.shape.radius });
                }
                break :collisions try collision.collisions(self.allocator, .{ xs.items, ys.items });
            };
            for (coll.items) |c| {
                var itX = q.from(c[0]);
                var itY = q.from(c[1]);
                if (itX.current()) |x| if (itY.current()) |y| if (collision.collide(x, y)) |dir| {
                    x.transform.position = x.transform.position.add(dir.scale(0.5));
                    y.transform.position = y.transform.position.subtract(dir.scale(0.5));
                    inline for (.{ &itX, &itY }, .{ &itY, &itX }) |itA, itB| {
                        if (itA.refine(struct { health: *config.Health, tag: config.EnemyTag }, &self.ecs)) |enemy| {
                            if (itB.refine(struct { tag: config.BulletTag }, &self.ecs)) |_| {
                                enemy.health[0] = if (enemy.health[0] < config.bullet.damage) 0 else enemy.health[0] - config.bullet.damage;
                                itB.destroy(&self.ecs);
                            }
                            if (itB.refine(struct { health: *config.Health, tag: config.PlayerTag }, &self.ecs)) |p| {
                                p.health[0] = if (p.health[0] < config.enemy.damage) 0 else p.health[0] - config.enemy.damage;
                            }
                        }
                    }
                };
            }
        }
        {
            var q = self.ecs.query(collision.Collider(config.Circle));
            var itX = q.iterator();
            while (itX.next()) |x| {
                var qWall = self.ecs.query(collision.Collider(config.Square));
                var itWall = qWall.iterator();
                while (itWall.next()) |wall| if (collision.collide(wall, x)) |dir| {
                    x.transform.position = x.transform.position.add(dir);
                };
            }
        }
        {
            var q = self.ecs.query(struct { deathTime: config.DeathTime });
            var it = q.iterator();
            while (it.next()) |x| if (x.deathTime[0] < rl.getTime()) it.destroy(&self.ecs);
        }
        {
            var q = self.ecs.query(struct { health: config.Health });
            var it = q.iterator();
            while (it.next()) |x| if (x.health[0] == 0) {
                if (it.refine(struct { config.EnemyTag }, &self.ecs)) |_|
                    self.score += config.player.reward;
                it.destroy(&self.ecs);
            };
        }
    }
};
