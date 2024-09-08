const rl = @import("raylib");
const std = @import("std");
const collision = @import("collision.zig");
const ecslib = @import("ecs.zig");

// speeds is in units per frame, rate is in objects per second
pub const config = .{
    .wall = .{ .height = 2.0, .size = 1.0 },
    .character = .{ .radius = 0.5, .height = 2, .speed = 0.1 },
    .bullet = .{ .radius = 0.1, .speed = 0.2, .damage = 10, .rate = 5.0, .lifetime = 2 },
    .player = .{ .health = 100, .reward = 1, .cameraDelta = rl.Vector3.init(0, 10, 4) },
    .enemy = .{ .speedFactor = 0.6, .spawnRate = 0.5, .health = 50, .damage = 2 },
    .map =
    \\ [][][][][][][][][][][][][][][][][][][][][][][][][][]
    \\ []                                                []
    \\ []                zs                              []
    \\ []                                    []          []
    \\ [][]    [][][][][][][][][]  [][][][][][]          []
    \\ []           []                       []          []
    \\ []           []         zs            []          []
    \\ []           []                       []          []
    \\ [][]    [][][][][][][][]      [][][][][]          []
    \\ []                []                  []          []
    \\ []      ps        []                  []          []
    \\ []                []                  []          []
    \\ [][][][][]    [][][][][][][]    [][][][]          []
    \\ []                                    []          []
    \\ []                                                []
    \\ []                                                []
    \\ [][][][][][][][][][][][][][][][][][][][][][][][][][]
    ,
};
const Controller = struct {
    shoot: bool,
    direction: rl.Vector2,
    delta: rl.Vector2,

    fn getInput() Controller {
        var shoot = false;
        const bindings = [_]struct { rl.KeyboardKey, rl.Vector2 }{
            .{ rl.KeyboardKey.key_w, .{ .x = 0, .y = 1 } },
            .{ rl.KeyboardKey.key_s, .{ .x = 0, .y = -1 } },
            .{ rl.KeyboardKey.key_a, .{ .x = 1, .y = 0 } },
            .{ rl.KeyboardKey.key_d, .{ .x = -1, .y = 0 } },
        };
        const vec = for (bindings) |kv| {
            if (rl.isKeyDown(kv[0])) break kv[1];
        } else rl.Vector2{ .x = 0, .y = 0 };

        if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left) or rl.isKeyDown(rl.KeyboardKey.key_space)) {
            shoot = true;
        }
        var dir = rl.getMousePosition();
        dir.x -= @as(f32, @floatFromInt(rl.getScreenWidth())) / 2;
        dir.y -= @as(f32, @floatFromInt(rl.getScreenHeight())) / 2;
        return Controller{
            .shoot = shoot,
            .direction = dir,
            .delta = vec.normalize().scale(config.character.speed).rotate(-std.math.atan2(dir.x, dir.y)),
        };
    }
};

const Collider = struct { transform: *Transform, collider: DynamicCollider };
fn dynamicCollide(x: Collider, y: Collider) ?rl.Vector2 {
    const dif = x.transform.position.subtract(y.transform.position);
    const scale = x.collider.radius + y.collider.radius - dif.length();
    return if (scale > 0) dif.normalize().scale(scale) else null;
}

fn directionTo(wall: anytype, x: Collider) ?rl.Vector2 {
    const sgnX: f32 = if (x.transform.position.x - wall.transform.position.x > 0) 1 else -1;
    const sgnY: f32 = if (x.transform.position.y - wall.transform.position.y > 0) 1 else -1;
    const difX = config.wall.size / 2.0 + x.collider.radius - @abs(x.transform.position.x - wall.transform.position.x);
    const difY = config.wall.size / 2.0 + x.collider.radius - @abs(x.transform.position.y - wall.transform.position.y);
    if (difX > 0 and difY > 0) return if (difX < difY) rl.Vector2.init(sgnX * difX, 0) else rl.Vector2.init(0, sgnY * difY);
    return null;
}
const Spawner = struct {
    position: rl.Vector2,
    nextSpawn: f64,
};

const Cell = enum { Wall, Player, Spawner };
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

const Health = struct { u32 };
const Transform = struct { position: rl.Vector2 };
const Direction = struct { rl.Vector2 };
const Gun = struct { lastFired: f64 };
const DeathTime = struct { f64 };
const DynamicCollider = struct { radius: f32 };
const WallTag = struct {};
const EnemyTag = struct {};
const BulletTag = struct {};
const PlayerTag = struct {};
const SpawnerTag = struct {};
const NextSpawn = struct { time: f64 };

const EnemySpawner = .{ Transform, NextSpawn, SpawnerTag };
const Player = .{ Transform, Health, Gun, DynamicCollider, PlayerTag };
const Bullet = .{ Transform, DeathTime, Direction, DynamicCollider, BulletTag };
const Enemy = .{ Transform, Health, EnemyTag, DynamicCollider };
const Wall = .{ Transform, WallTag };
// TODO different max_entities for different entities
const Ecs = ecslib.Ecs(.{ Player, Bullet, Enemy, Wall, EnemySpawner });

const Status = union(enum) {
    score: u32,
    health: f32,
};

pub const World = struct {
    score: u32,
    camera: rl.Camera3D,
    allocator: std.mem.Allocator,
    ecs: Ecs,
    cells: std.AutoHashMap(Position, Cell),
    pub fn init(allocator: std.mem.Allocator) !World {
        const cells = try mapToCells(allocator);
        var ecs = try Ecs.init(allocator, 1000);
        {
            var it = cells.iterator();
            const pos = while (it.next()) |cell| {
                if (cell.value_ptr.* == Cell.Player)
                    break cell.key_ptr.toVec2();
            } else rl.Vector2.init(0, 0);
            ecs.add(.{ Health{config.player.health}, Transform{ .position = pos }, Gun{ .lastFired = 0 }, DynamicCollider{ .radius = config.character.radius }, PlayerTag{} });
        }
        const camera = rl.Camera3D{
            .position = config.player.cameraDelta,
            .target = rl.Vector3.zero(),
            .up = rl.Vector3.init(0, 1, 0),
            .fovy = 60,
            .projection = rl.CameraProjection.camera_perspective,
        };
        {
            var it = cells.iterator();
            while (it.next()) |entry| switch (entry.value_ptr.*) {
                .Wall => ecs.add(.{ Transform{ .position = entry.key_ptr.toVec2() }, WallTag{} }),
                .Player => {},
                .Spawner => ecs.add(.{ Transform{ .position = entry.key_ptr.toVec2() }, NextSpawn{ .time = 0.0 }, SpawnerTag{} }),
            };
        }
        return .{ .allocator = allocator, .ecs = ecs, .camera = camera, .cells = cells, .score = 0 };
    }
    pub fn getStatus(self: *World) Status {
        var q = self.ecs.query(struct { health: Health, tag: PlayerTag });
        var it = q.iterator();
        return if (it.next()) |x| .{ .health = @as(f32, @floatFromInt(x.health[0])) / config.player.health } else .{ .score = self.score };
    }
    pub fn update(self: *World) !void {
        const movement = Controller.getInput();
        {
            var q = self.ecs.query(struct { transform: Transform, nextSpawn: *NextSpawn, tag: SpawnerTag });
            var it = q.iterator();
            while (it.next()) |spawner| {
                if (rl.getTime() < spawner.nextSpawn.time) continue;
                spawner.nextSpawn.time = rl.getTime() + 1.0 / config.enemy.spawnRate;
                self.ecs.add(.{
                    .health = Health{config.enemy.health},
                    .transform = Transform{ .position = spawner.transform.position },
                    .collider = DynamicCollider{ .radius = config.character.radius },
                    .tag = EnemyTag{},
                });
            }
        }
        const hints = hints: {
            var q = self.ecs.query(struct { transform: *Transform, tag: PlayerTag });
            var it = q.iterator();
            var player = it.next().?;
            std.debug.assert(it.next() == null);
            player.transform.position = player.transform.position.add(movement.delta);
            const pos3d = rl.Vector3.init(player.transform.position.x, 0, player.transform.position.y);
            self.camera.position = pos3d.add(config.player.cameraDelta);
            self.camera.target = pos3d;
            break :hints try getHints(self.allocator, player.transform.position, self.cells);
        };
        {
            var q = self.ecs.query(struct { transform: *Transform, tag: EnemyTag });
            var it = q.iterator();
            while (it.next()) |enemy| {
                if (hints.get(Position.fromVec2(enemy.transform.position))) |h| {
                    enemy.transform.position = h.toVec2()
                        .subtract(enemy.transform.position)
                        .normalize().scale(config.character.speed * config.enemy.speedFactor)
                        .add(enemy.transform.position);
                } else {
                    std.log.debug("No hint for enemy at {}", .{enemy.transform.position});
                }
            }
        }
        // TODO bullets going through walls (when one over the other)
        {
            var q = self.ecs.query(struct { transform: *Transform, dir: Direction });
            var it = q.iterator();
            while (it.next()) |bullet| {
                bullet.transform.position = bullet.transform.position.add(bullet.dir[0].normalize().scale(config.bullet.speed));
            }
        }
        if (movement.shoot) {
            var q = self.ecs.query(struct { transform: Transform, gun: *Gun });
            var it = q.iterator();
            while (it.next()) |player| {
                const isReadyToFire = player.gun.lastFired + 1.0 / config.bullet.rate < rl.getTime();
                if (isReadyToFire) {
                    self.ecs.add(.{
                        Transform{ .position = movement.direction.normalize()
                            .scale(config.character.radius + config.bullet.radius)
                            .add(player.transform.position) },
                        DeathTime{rl.getTime() + config.bullet.lifetime},
                        Direction{movement.direction},
                        DynamicCollider{ .radius = config.bullet.radius },
                        BulletTag{},
                    });
                    player.gun.lastFired = rl.getTime();
                }
            }
        }
        {
            var q = self.ecs.query(Collider);
            var it = q.iterator();
            var xs = try std.ArrayList(collision.Segment).initCapacity(self.allocator, 100);
            var ys = try std.ArrayList(collision.Segment).initCapacity(self.allocator, 100);
            while (it.next()) |e| {
                try xs.append(.{ .min = e.transform.position.x - e.collider.radius, .max = e.transform.position.x + e.collider.radius });
                try ys.append(.{ .min = e.transform.position.y - e.collider.radius, .max = e.transform.position.y + e.collider.radius });
            }
            const coll = try collision.collisions(self.allocator, .{ xs.items, ys.items });
            for (coll.items) |c| {
                var itX = q.from(c[0]);
                var itY = q.from(c[1]);
                if (itX.current()) |x| if (itY.current()) |y| if (dynamicCollide(x, y)) |dir| {
                    x.transform.position = x.transform.position.add(dir.scale(0.5));
                    y.transform.position = y.transform.position.subtract(dir.scale(0.5));
                    if (itY.refine(struct { health: *Health, tag: EnemyTag }, &self.ecs)) |enemy| {
                        if (itX.refine(struct { tag: BulletTag }, &self.ecs)) |_| {
                            enemy.health[0] = if (enemy.health[0] < config.bullet.damage) 0 else enemy.health[0] - config.bullet.damage;
                            itX.destroy(&self.ecs);
                        }
                        if (itX.refine(struct { health: *Health, tag: PlayerTag }, &self.ecs)) |p| {
                            p.health[0] = if (p.health[0] < config.enemy.damage) 0 else p.health[0] - config.enemy.damage;
                        }
                    }
                };
            }
        }
        {
            var q = self.ecs.query(Collider);
            var itX = q.iterator();
            while (itX.next()) |x| {
                // var itY = q.iterator();
                // while (itY.next()) |y| if (dynamicCollide(x, y)) |dir| {
                //     x.transform.position = x.transform.position.add(dir.scale(0.5));
                //     y.transform.position = y.transform.position.subtract(dir.scale(0.5));
                //     if (itY.refine(struct { health: *Health, tag: EnemyTag }, &self.ecs)) |enemy| {
                //         if (itX.refine(struct { tag: BulletTag }, &self.ecs)) |_| {
                //             enemy.health[0] = if (enemy.health[0] < config.bullet.damage) 0 else enemy.health[0] - config.bullet.damage;
                //             itX.destroy(&self.ecs);
                //         }
                //         if (itX.refine(struct { health: *Health, tag: PlayerTag }, &self.ecs)) |p| {
                //             p.health[0] = if (p.health[0] < config.enemy.damage) 0 else p.health[0] - config.enemy.damage;
                //         }
                //     }
                // };
                var qWall = self.ecs.query(struct { transform: Transform, tag: WallTag });
                var itWall = qWall.iterator();
                while (itWall.next()) |wall| if (directionTo(wall, x)) |dir| {
                    x.transform.position = x.transform.position.add(dir);
                };
            }
        }
        {
            var q = self.ecs.query(struct { deathTime: DeathTime });
            var it = q.iterator();
            while (it.next()) |x| if (x.deathTime[0] < rl.getTime()) it.destroy(&self.ecs);
        }
        {
            var q = self.ecs.query(struct { health: Health });
            var it = q.iterator();
            while (it.next()) |x| if (x.health[0] == 0) {
                if (it.refine(struct { EnemyTag }, &self.ecs)) |_|
                    self.score += config.player.reward;
                it.destroy(&self.ecs);
            };
        }
    }
    pub fn draw(self: *World) void {
        self.camera.begin();
        defer self.camera.end();

        for (0..100) |i| {
            for (0..100) |j| {
                const x: f32 = @floatFromInt(i);
                const z: f32 = @floatFromInt(j);
                rl.drawPlane(rl.Vector3.init(x - 50, 0, z - 50), rl.Vector2.init(1, 1), if ((i + j) % 2 == 0) rl.Color.white else rl.Color.blue);
            }
        }
        {
            var q = self.ecs.query(struct { transform: Transform, tag: PlayerTag });
            var it = q.iterator();
            while (it.next()) |player| {
                const start = rl.Vector3.init(player.transform.position.x, config.character.radius, player.transform.position.y);
                const end = rl.Vector3.init(player.transform.position.x, config.character.height - config.character.radius, player.transform.position.y);
                rl.drawCapsule(start, end, config.character.radius, 10, 1, rl.Color.light_gray);
            }
        }
        {
            var q = self.ecs.query(struct { transform: Transform, tag: BulletTag });
            var it = q.iterator();
            while (it.next()) |bullet| {
                const pos = rl.Vector3.init(bullet.transform.position.x, 1.2, bullet.transform.position.y);
                rl.drawSphere(pos, config.bullet.radius, rl.Color.white);
            }
        }
        {
            var q = self.ecs.query(struct { transform: Transform, health: Health, tag: EnemyTag });
            var it = q.iterator();
            while (it.next()) |enemy| {
                const start = rl.Vector3.init(enemy.transform.position.x, config.character.radius, enemy.transform.position.y);
                const end = rl.Vector3.init(enemy.transform.position.x, config.character.height - config.character.radius, enemy.transform.position.y);
                const color = rl.Color.fromNormalized(rl.Vector4.init(@as(f32, @floatFromInt(enemy.health[0])) / config.enemy.health, 0, 0.2, 1));
                rl.drawCapsule(start, end, config.character.radius, 10, 1, color);
            }
        }
        {
            var q = self.ecs.query(struct { transform: Transform, tag: WallTag });
            var it = q.iterator();
            while (it.next()) |wall| {
                const pos = rl.Vector3.init(wall.transform.position.x, 1, wall.transform.position.y);
                const size = rl.Vector3.init(config.wall.size, config.wall.height, config.wall.size);
                rl.drawCubeV(pos, size, rl.Color.dark_blue);
            }
        }
    }
};
