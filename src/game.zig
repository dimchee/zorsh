const rl = @import("raylib");
const std = @import("std");
const coll = @import("collision.zig");
const ecslib = @import("ecs.zig");

// speeds is in units per frame, rate is in objects per second
pub const config = .{
    .wall = .{ .height = 2, .size = 1 },
    .character = .{ .radius = 0.5, .height = 2, .speed = 0.1 },
    .bullet = .{ .radius = 0.1, .speed = 0.1, .damage = 10, .rate = 5.0, .lifetime = 2 },
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

const Wall = struct {
    position: rl.Vector2,
    size: rl.Vector3,
    fn init(pos: rl.Vector2) Wall {
        return .{ .position = pos, .size = rl.Vector3.init(config.wall.size, config.wall.height, config.wall.size) };
    }
    fn draw(self: *const Wall) void {
        const pos = rl.Vector3.init(self.position.x, 1, self.position.y);
        rl.drawCubeV(pos, self.size, rl.Color.dark_blue);
    }
    fn directionTo(self: *const Wall, p: rl.Vector2) rl.Vector2 {
        const delta = rl.Vector2.init(self.size.x / 2, self.size.z / 2);
        const rect = .{ .min = self.position.subtract(delta), .max = self.position.add(delta) };
        return rl.Vector2.init(
            @min(p.x - rect.min.x, 0) + @max(p.x - rect.max.x, 0),
            @min(p.y - rect.min.y, 0) + @max(p.y - rect.max.y, 0),
        );
    }
    fn projectX(self: *const Wall) coll.Segment {
        return .{ .min = self.position.x - self.size.x / 2, .max = self.position.x + self.size.x / 2 };
    }
    fn projectY(self: *const Wall) coll.Segment {
        return .{ .min = self.position.y - self.size.z / 2, .max = self.position.y + self.size.z / 2 };
    }
};
fn Spawner(what: type) type {
    return struct {
        position: rl.Vector2,
        nextSpawn: f64,
        fn init(position: rl.Vector2) Spawner(what) {
            return .{ .position = position, .nextSpawn = 0.0 };
        }
        fn spawn(self: *Spawner(what)) ?what {
            if (rl.getTime() < self.nextSpawn) return null;
            self.nextSpawn = rl.getTime() + 1.0 / config.enemy.spawnRate;
            return what.init(self.position);
        }
    };
}

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

const Dungeon = struct {
    walls: std.ArrayList(Wall),
    spawners: std.ArrayList(Spawner(Enemy3)),
    rng: std.rand.DefaultPrng,
    fn init(allocator: std.mem.Allocator, cells: std.AutoHashMap(Position, Cell)) !Dungeon {
        var walls = std.ArrayList(Wall).init(allocator);
        var spawners = std.ArrayList(Spawner(Enemy3)).init(allocator);
        var it = cells.iterator();
        while (it.next()) |cell| {
            switch (cell.value_ptr.*) {
                Cell.Wall => try walls.append(Wall.init(cell.key_ptr.toVec2())),
                Cell.Spawner => try spawners.append(Spawner(Enemy3).init(cell.key_ptr.toVec2())),
                Cell.Player => {},
            }
        }
        return .{
            .walls = walls,
            .spawners = spawners,
            .rng = std.rand.DefaultPrng.init(0),
        };
    }
    fn draw(self: *const Dungeon) void {
        for (self.walls.items) |w| {
            w.draw();
        }
    }
};

fn hints(allocator: std.mem.Allocator, target: rl.Vector2, cells: std.AutoHashMap(Position, Cell)) !std.AutoHashMap(Position, Position) {
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
const Score = struct { u32 };
const Transform = struct { position: rl.Vector2 };
const Direction = struct { rl.Vector2 };
const Camera = struct { rl.Camera3D };
const NewGun = struct { lastFired: f64 };
const DeathTime = struct { f64 };
const DynamicCollider = struct { radius: f32 };
const WallTag = struct {};
const EnemyTag = struct {};
const BulletTag = struct {};
const PlayerTag = struct {};

const Player = .{ Transform, Camera, Health, Score, NewGun, DynamicCollider, PlayerTag };
const Bullet = .{ Transform, DeathTime, Direction, DynamicCollider, BulletTag };
const Enemy = .{ Transform, Health, EnemyTag, DynamicCollider };
const Wall2 = .{ Transform, WallTag };
const Enemy3 = struct {
    transform: Transform,
    health: Health,
    tag: EnemyTag,
    collider: DynamicCollider,
    fn init(position: rl.Vector2) @This() {
        return .{ .transform = .{ .position = position }, .health = .{config.enemy.health}, .tag = EnemyTag{}, .collider = DynamicCollider{ .radius = config.character.radius } };
    }
};

// different max_entities for different entities
pub const World = struct {
    const Ecs = ecslib.Ecs(.{ Player, Bullet, Enemy, Wall2 });
    allocator: std.mem.Allocator,
    dungeon: Dungeon,
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
            ecs.add(.{ Health{config.player.health}, Score{0}, Transform{ .position = pos }, Camera{
                rl.Camera3D{
                    .position = config.player.cameraDelta,
                    .target = rl.Vector3.zero(),
                    .up = rl.Vector3.init(0, 1, 0),
                    .fovy = 60,
                    .projection = rl.CameraProjection.camera_perspective,
                },
            }, NewGun{ .lastFired = 0 }, DynamicCollider{ .radius = config.character.radius }, PlayerTag{} });
        }
        return .{
            .allocator = allocator,
            .dungeon = try Dungeon.init(allocator, cells),
            .ecs = ecs,
            .cells = cells,
        };
    }
    pub fn getPlayerStats(self: *World) struct { health: f32, score: u32 } {
        var q = self.ecs.query(struct { health: *Health, score: *Score, position: *Transform, camera: *Camera, gun: NewGun });
        var it = q.iterator();
        while (it.next()) |player| return .{ .health = @floatFromInt(player.health[0]), .score = player.score[0] };
        return .{ .health = 0, .score = 0 };
    }
    pub fn update(self: *World) !void {
        const movement = Controller.getInput();
        for (self.dungeon.spawners.items) |*spawner| {
            if (spawner.spawn()) |enemy| {
                self.ecs.add(enemy);
            }
        }
        var playerQ = self.ecs.query(struct { health: *Health, score: *Score, transform: *Transform, camera: *Camera, gun: *NewGun });
        var playerIt = playerQ.iterator();
        var player = playerIt.next().?;
        player.transform.position = player.transform.position.add(movement.delta);
        const pos3d = rl.Vector3.init(player.transform.position.x, 0, player.transform.position.y);
        player.camera[0].position = pos3d.add(config.player.cameraDelta);
        player.camera[0].target = pos3d;
        {
            var enemyQ = self.ecs.query(struct { transform: *Transform, tag: EnemyTag });
            var enemyIt = enemyQ.iterator();
            while (enemyIt.next()) |enemy| {
                enemy.transform.position = (try hints(self.allocator, player.transform.position, self.cells))
                    .get(Position.fromVec2(enemy.transform.position)).?.toVec2()
                    .subtract(enemy.transform.position)
                    .normalize().scale(config.character.speed * config.enemy.speedFactor)
                    .add(enemy.transform.position);
            }
        }

        if (movement.shoot) {
            const isReadyToFire = player.gun.lastFired + 1.0 / config.bullet.rate < rl.getTime();
            if (isReadyToFire) {
                self.ecs.add(.{
                    Transform{ .position = movement.direction.normalize()
                        .scale(config.character.radius + config.bullet.radius * 1.001)
                        .add(player.transform.position) },
                    DeathTime{rl.getTime() + config.bullet.lifetime},
                    Direction{movement.direction},
                    DynamicCollider{ .radius = config.bullet.radius },
                    BulletTag{},
                });
                player.gun.lastFired = rl.getTime();
            }
        }
        {
            var bq = self.ecs.query(struct { transform: *Transform, deathTime: DeathTime, dir: Direction });
            var bIt = bq.iterator();
            while (bIt.next()) |bullet| {
                bullet.transform.position = bullet.transform.position.add(bullet.dir[0].normalize().scale(config.bullet.speed));
            }
        }
        {
            var dynamicQ = self.ecs.query(Collider);
            var dynamicIt1 = dynamicQ.iterator();
            while (dynamicIt1.next()) |x| {
                var dynamicIt2 = dynamicQ.iterator();
                while (dynamicIt2.next()) |y| {
                    if (dynamicCollide(x, y)) |dir| {
                        x.transform.position = x.transform.position.add(dir.scale(0.5));
                        y.transform.position = y.transform.position.subtract(dir.scale(0.5));
                        if (dynamicIt2.refine(struct { health: *Health, tag: EnemyTag }, &self.ecs)) |enemy| {
                            if (dynamicIt1.refine(struct { tag: BulletTag }, &self.ecs)) |_| {
                                enemy.health[0] = if (enemy.health[0] < config.bullet.damage) 0 else enemy.health[0] - config.bullet.damage;
                                dynamicIt1.destroy(&self.ecs);
                            }
                            if (dynamicIt1.refine(struct { health: *Health, tag: PlayerTag }, &self.ecs)) |p| {
                                p.health[0] = if (p.health[0] < config.enemy.damage) 0 else p.health[0] - config.enemy.damage;
                            }
                        }
                    }
                }
                for (self.dungeon.walls.items) |*wall| {
                    const dir = wall.directionTo(x.transform.position);
                    if (dir.lengthSqr() < x.collider.radius * x.collider.radius) {
                        x.transform.position = dir.normalize().scale(x.collider.radius - dir.length()).add(x.transform.position);
                    }
                }
            }
        }
        {
            var q = self.ecs.query(struct { deathTime: DeathTime });
            var it = q.iterator();
            while (it.next()) |x| if (x.deathTime[0] < rl.getTime()) it.destroy(&self.ecs);
        }
        {
            var q = self.ecs.query(struct { health: Health, tag: EnemyTag });
            var it = q.iterator();
            while (it.next()) |x| if (x.health[0] == 0) {
                it.destroy(&self.ecs);
                player.score[0] += config.player.reward;
            };
        }
    }
    pub fn draw(self: *World) void {
        var playerQ = self.ecs.query(struct { camera: *Camera, transform: Transform, tag: PlayerTag });
        var playerIt = playerQ.iterator();
        var player = playerIt.next().?;

        player.camera[0].begin();
        defer player.camera[0].end();

        for (0..100) |i| {
            for (0..100) |j| {
                const x: f32 = @floatFromInt(i);
                const z: f32 = @floatFromInt(j);
                rl.drawPlane(rl.Vector3.init(x - 50, 0, z - 50), rl.Vector2.init(1, 1), if ((i + j) % 2 == 0) rl.Color.white else rl.Color.blue);
            }
        }
        {
            const start = rl.Vector3.init(player.transform.position.x, config.character.radius, player.transform.position.y);
            const end = rl.Vector3.init(player.transform.position.x, config.character.height - config.character.radius, player.transform.position.y);
            rl.drawCapsule(start, end, config.character.radius, 10, 1, rl.Color.light_gray);
        }
        {
            var q = self.ecs.query(struct { transform: Transform, deathTime: DeathTime });
            var it = q.iterator();
            while (it.next()) |bullet| {
                const pos = rl.Vector3.init(bullet.transform.position.x, 1.2, bullet.transform.position.y);
                rl.drawSphere(pos, config.bullet.radius, rl.Color.white);
            }
        }
        {
            var enemyQ = self.ecs.query(struct { transform: Transform, health: Health, tag: EnemyTag });
            var enemyIt = enemyQ.iterator();
            while (enemyIt.next()) |enemy| {
                const start = rl.Vector3.init(enemy.transform.position.x, config.character.radius, enemy.transform.position.y);
                const end = rl.Vector3.init(enemy.transform.position.x, config.character.height - config.character.radius, enemy.transform.position.y);
                rl.drawCapsule(start, end, config.character.radius, 10, 1, rl.Color.fromNormalized(rl.Vector4.init(
                    @as(f32, @floatFromInt(enemy.health[0])) / @as(f32, config.enemy.health),
                    0,
                    0.2,
                    1,
                )));
            }
        }
        self.dungeon.draw();
    }
};
