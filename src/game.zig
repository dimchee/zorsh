const rl = @import("raylib");
const std = @import("std");
const collision = @import("collision.zig");
const config = @import("config.zig");

const Status = union(enum) {
    score: u32,
    healthPercentage: f32,
};

pub const Input = struct {
    shoot: bool,
    movement: rl.Vector2,
    direction: rl.Vector2,
};

fn fromPos(pos: config.Position) rl.Vector2 {
    return rl.Vector2.init(@floatFromInt(pos.x), @floatFromInt(pos.y));
}
fn toPos(vec: rl.Vector2) config.Position {
    return .{ .x = @intFromFloat(vec.x + 0.5), .y = @intFromFloat(vec.y + 0.5) };
}

pub const World = struct {
    score: u32,
    allocator: std.mem.Allocator,
    ecs: config.Ecs,
    pub fn init(allocator: std.mem.Allocator) !World {
        var ecs = try config.Ecs.init(allocator, 1000);
        {
            const pos = for (config.Map.items, 0..) |cell, ind| {
                if (cell == .Player) if (config.Map.toPos(ind)) |v| break fromPos(v);
            } else rl.Vector2.init(0, 0);
            ecs.add(.{
                config.Health{config.player.health},
                config.Transform{ .position = pos },
                config.Gun{ .lastFired = 0 },
                config.Circle{ .radius = config.character.radius },
                config.PlayerTag{},
            });
        }
        {
            for (config.Map.items, 0..) |cell, ind| switch (cell) {
                .Wall => ecs.add(.{
                    config.Transform{ .position = fromPos(config.Map.toPos(ind).?) },
                    config.Rectangle{ .size = rl.Vector2.init(config.wall.size, config.wall.size) },
                    config.WallTag{},
                }),
                .Player => {},
                .Empty => {},
                .Spawner => ecs.add(.{
                    config.Transform{ .position = fromPos(config.Map.toPos(ind).?) },
                    config.NextSpawn{ .time = 0.0 },
                    config.SpawnerTag{},
                }),
            };
        }
        return .{ .allocator = allocator, .ecs = ecs, .score = 0 };
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
            break :hints config.Map.getHints(toPos(player.transform.position));
        };
        {
            var q = self.ecs.query(struct { transform: *config.Transform, tag: config.EnemyTag });
            var it = q.iterator();
            while (it.next()) |enemy| {
                if (hints.get(toPos(enemy.transform.position))) |hint| {
                    enemy.transform.position = fromPos(hint)
                        .subtract(enemy.transform.position)
                        .normalize().scale(config.character.speed * config.enemy.speedFactor)
                        .add(enemy.transform.position);
                } else {
                    std.log.warn("No hint for enemy at {}", .{enemy.transform.position});
                }
            }
        }
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
                            .scale(config.character.radius + config.bullet.radius * 1.1)
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
                        if (itA.refine(struct { health: *config.Health }, &self.ecs)) |vulnerable|
                            if (itB.refine(struct { tag: config.BulletTag }, &self.ecs)) |_| {
                                vulnerable.health[0] -= @min(vulnerable.health[0], config.bullet.damage);
                                itB.destroy(&self.ecs);
                            };
                        if (itA.refine(struct { health: *config.Health, tag: config.EnemyTag }, &self.ecs)) |_|
                            if (itB.refine(struct { health: *config.Health, tag: config.PlayerTag }, &self.ecs)) |player| {
                                player.health[0] -= @min(player.health[0], config.enemy.damage);
                            };
                    }
                };
            }
        }
        {
            var q = self.ecs.query(collision.Collider(config.Circle));
            var itX = q.iterator();
            while (itX.next()) |x| {
                var qWall = self.ecs.query(collision.Collider(config.Rectangle));
                var itWall = qWall.iterator();
                while (itWall.next()) |wall| if (collision.collide(wall, x)) |dir| {
                    if (itX.refine(struct { dir: *config.Direction, tag: config.BulletTag }, &self.ecs)) |b|
                        b.dir[0] = b.dir[0].reflect(dir.normalize());
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
