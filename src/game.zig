const rl = @import("raylib");
const std = @import("std");
const collision = @import("collision.zig");
const config = @import("config.zig");

const Status = union(enum) {
    score: u32,
    hp: f32,
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
        var ecs = try config.Ecs.init(allocator, 500);
        {
            const pos = for (config.Map.items, 0..) |cell, ind| {
                if (cell == .Player) if (config.Map.toPos(ind)) |v| break fromPos(v);
            } else rl.Vector2.init(0, 0);
            ecs.add(.{
                config.Health{config.player.health},
                config.Transform{ .position = pos },
                config.Physics{ .velocity = rl.Vector2.zero() },
                config.Gun{ .lastFired = 0, .angle = 0, .triggered = false },
                config.Circle{ .radius = config.character.radius },
                config.PlayerTag{},
            });
        }
        {
            for (config.Map.items, 0..) |cell, ind| switch (cell) {
                .Spawner => ecs.add(.{
                    config.Transform{ .position = fromPos(config.Map.toPos(ind).?) },
                    config.NextSpawn{ .time = 0.0 },
                    config.SpawnerTag{},
                }),
                else => {},
            };
        }
        return .{ .allocator = allocator, .ecs = ecs, .score = 0 };
    }
    pub fn getStatus(self: *World) Status {
        var q = self.ecs.query(struct { health: config.Health, tag: config.PlayerTag });
        var it = q.iterator();
        return if (it.next()) |x| .{ .hp = @as(f32, @floatFromInt(x.health[0])) / config.player.health } else .{ .score = self.score };
    }
    pub fn update(self: *World, input: Input) !void {
        // Input
        const hints = hints: {
            var q = self.ecs.query(struct { transform: config.Transform, physics: *config.Physics, gun: *config.Gun, tag: config.PlayerTag });
            var it = q.iterator();
            var player = it.next().?;
            std.debug.assert(it.next() == null);
            player.gun.triggered = input.shoot;
            player.gun.angle = rl.Vector2.init(0, 1).angle(input.direction);
            player.physics.velocity = input.movement.scale(-config.character.speed);
            break :hints config.Map.getHints(toPos(player.transform.position));
        };
        {
            var q = self.ecs.query(struct { transform: config.Transform, physics: *config.Physics, tag: config.EnemyTag });
            var it = q.iterator();
            while (it.next()) |enemy| if (hints.get(toPos(enemy.transform.position))) |hint| {
                enemy.physics.velocity = hint.normalize().scale(config.character.speed * config.enemy.speedFactor);
            };
        }
        // Spawning
        {
            var q = self.ecs.query(struct { transform: config.Transform, nextSpawn: *config.NextSpawn, tag: config.SpawnerTag });
            var it = q.iterator();
            while (it.next()) |spawner| {
                if (rl.getTime() < spawner.nextSpawn.time) continue;
                spawner.nextSpawn.time = rl.getTime() + 1.0 / config.enemy.spawnRate;
                self.ecs.add(.{
                    .health = config.Health{config.enemy.health},
                    .transform = config.Transform{ .position = spawner.transform.position },
                    .physics = config.Physics{ .velocity = rl.Vector2.zero() },
                    .shape = config.Circle{ .radius = config.character.radius },
                    .tag = config.EnemyTag{},
                });
            }
        }
        {
            var q = self.ecs.query(struct { transform: config.Transform, gun: *config.Gun });
            var it = q.iterator();
            while (it.next()) |shooter| {
                const isReadyToFire = shooter.gun.lastFired + 1.0 / config.bullet.rate < rl.getTime();
                if (isReadyToFire and shooter.gun.triggered) {
                    const dir = rl.Vector2.init(0, 1).rotate(shooter.gun.angle);
                    const dist = config.character.radius + config.bullet.radius * 1.1;
                    const pos = dir.scale(dist).add(shooter.transform.position);
                    self.ecs.add(.{
                        config.Transform{ .position = pos },
                        config.DeathTime{rl.getTime() + config.bullet.lifetime},
                        config.Physics{ .velocity = dir.scale(config.bullet.speed) },
                        config.Circle{ .radius = config.bullet.radius },
                        config.BulletTag{},
                    });
                    shooter.gun.lastFired = rl.getTime();
                }
            }
        }
        // Physics
        {
            var q = self.ecs.query(struct { transform: *config.Transform, physics: config.Physics });
            var it = q.iterator();
            while (it.next()) |x|
                x.transform.position = x.transform.position.add(x.physics.velocity);
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
                    inline for (.{ &itX, &itY }, .{ &itY, &itX }, .{ 0.5, -0.5 }) |itA, itB, scale| {
                        if (itA.refine(struct { *config.Transform }, &self.ecs)) |a|
                            a[0].position = a[0].position.add(dir.scale(scale));
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
                for (config.Map.walls) |wallPos| {
                    const wall = collision.Collider(config.Rectangle){
                        .transform = .{ .position = fromPos(wallPos) },
                        .shape = .{ .size = rl.Vector2.init(config.wall.size, config.wall.size) },
                    };
                    if (collision.collide(wall, x)) |dir| {
                        if (itX.refine(struct { physics: *config.Physics, tag: config.BulletTag }, &self.ecs)) |b|
                            b.physics.velocity = b.physics.velocity.reflect(dir.normalize());
                        if (itX.refine(struct { *config.Transform }, &self.ecs)) |a|
                            a[0].position = a[0].position.add(dir);
                    }
                }
            }
        }
        // Destroying
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
